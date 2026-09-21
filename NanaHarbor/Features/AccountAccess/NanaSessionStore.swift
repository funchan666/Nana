import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

struct NanaAccountProfile: Codable, Equatable {
    let emailAddress: String
    var displayName: String
    var gender: String
    var country: String
    var birthDate: Date?
    var interests: [String]
    var avatarData: Data?
    let signInMethod: String
    let appleUserID: String?

    /// Apple identities never share a local account with the email-only entry flow.
    var localAccountScope: String {
        if let appleUserID {
            let digest = SHA256.hash(data: Data(appleUserID.utf8)).map { String(format: "%02x", $0) }.joined()
            return "apple.\(digest)"
        }
        return "email.\(emailAddress.lowercased())"
    }
}

struct NanaPendingIdentity: Codable {
    let emailAddress: String
    let displayName: String
    let signInMethod: String
    let appleUserID: String?
}

private struct NanaLocalAccountLedger: Codable {
    var profiles: [String: NanaAccountProfile] = [:]
    var activeAccountScope: String?
    var pendingIdentity: NanaPendingIdentity?
    // Apple may return name/email only on the first authorization. Retain them
    // even when the user leaves profile completion and signs in again later.
    var appleIntroductions: [String: NanaPendingIdentity] = [:]
}

enum NanaLocalAccountError: LocalizedError {
    case invalidEntry, missingIdentity, incompleteProfile, storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidEntry: return "Enter a valid email address and a password of 8–128 characters."
        case .missingIdentity: return "Please return to sign-in and start again."
        case .incompleteProfile: return "Add your name, gender, country, date of birth and at least one tag."
        case .storageUnavailable: return "Nana couldn't save your details on this device. Please unlock your device and try again."
        }
    }
}

@MainActor
final class NanaSessionStore: ObservableObject {
    @Published private(set) var activeProfile: NanaAccountProfile?
    @Published private(set) var pendingIdentity: NanaPendingIdentity?
    @Published private(set) var onboardingFinished: Bool
    @Published var sessionNotice: AccountEntryNotice?

    private let defaults: UserDefaults
    private let onboardingKey = "nana.onboardingFinished.v1"
    private let keychainService = "com.nanalantern.harbortide.local-accounts"
    private var ledger = NanaLocalAccountLedger()
    private var ledgerLoaded = false
    private var sessionRevision = UUID()
    private var checkingAppleCredential = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingFinished = defaults.bool(forKey: onboardingKey)
        // Restore after the app is active, when protected Keychain data is available.
    }

    var isSignedIn: Bool { activeProfile != nil }

    func finishOnboarding() {
        onboardingFinished = true
        defaults.set(true, forKey: onboardingKey)
    }

    func restoreLocalSession() async {
        do {
            try loadLedgerIfNeeded()
            let profile = ledger.activeAccountScope.flatMap { ledger.profiles[$0] }
            if profile?.signInMethod != "apple" { activeProfile = profile }
            if ledger.pendingIdentity?.signInMethod != "apple" { pendingIdentity = ledger.pendingIdentity }
            await validateAppleSession()
        } catch {
            showStorageNotice()
        }
    }

    /// This is a local format-only entry gate, not password or mailbox verification.
    /// The password is deliberately neither compared, persisted nor transmitted.
    func signIn(emailAddress: String, password: String) throws {
        let entry = AccountEntryDraft(emailAddress: emailAddress, accountPassword: password)
        guard entry.validationMessage(for: .signIn) == nil else { throw NanaLocalAccountError.invalidEntry }
        try loadLedgerIfNeeded()
        let email = entry.normalizedEmailAddress
        let scope = "email.\(email)"
        let profile = ledger.profiles[scope] ?? NanaAccountProfile(
            emailAddress: email, displayName: "Nana member", gender: "", country: "",
            birthDate: nil, interests: [], avatarData: nil, signInMethod: "password", appleUserID: nil
        )
        try activate(profile)
    }

    func preparePasswordRegistration(emailAddress: String, password: String) throws {
        let entry = AccountEntryDraft(emailAddress: emailAddress, accountPassword: password)
        guard entry.validationMessage(for: .createAccount) == nil else { throw NanaLocalAccountError.invalidEntry }
        try loadLedgerIfNeeded()
        var updated = ledger
        updated.pendingIdentity = NanaPendingIdentity(emailAddress: entry.normalizedEmailAddress,
            displayName: ledger.profiles["email.\(entry.normalizedEmailAddress)"]?.displayName ?? "",
            signInMethod: "password", appleUserID: nil)
        try persist(updated)
        sessionRevision = UUID()
        pendingIdentity = updated.pendingIdentity
    }

    /// Called only after a successful AuthenticationServices authorization.
    /// Returns true for a completed local profile, false when details are needed.
    func acceptAppleAuthorization(_ identity: AppleIdentityResult) throws -> Bool {
        guard !identity.stableIdentity.isEmpty else { throw NanaLocalAccountError.missingIdentity }
        try loadLedgerIfNeeded()
        if let profile = ledger.profiles.values.first(where: { $0.appleUserID == identity.stableIdentity }) {
            try activate(profile)
            return true
        }
        let remembered = ledger.appleIntroductions[identity.stableIdentity]
        let suppliedName = identity.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suppliedEmail = identity.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let pending = NanaPendingIdentity(
            emailAddress: suppliedEmail.isEmpty ? remembered?.emailAddress ?? "" : suppliedEmail,
            displayName: suppliedName.isEmpty ? remembered?.displayName ?? "" : suppliedName,
            signInMethod: "apple", appleUserID: identity.stableIdentity
        )
        var updated = ledger
        updated.pendingIdentity = pending
        updated.appleIntroductions[identity.stableIdentity] = pending
        try persist(updated)
        sessionRevision = UUID()
        pendingIdentity = pending
        return false
    }

    func completeProfile(displayName: String, gender: String, country: String, birthDate: Date, interests: [String], avatarData: Data?) throws {
        guard let identity = pendingIdentity else { throw NanaLocalAccountError.missingIdentity }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !gender.isEmpty, !country.isEmpty, !interests.isEmpty, birthDate <= Date() else {
            throw NanaLocalAccountError.incompleteProfile
        }
        try activate(NanaAccountProfile(emailAddress: identity.emailAddress, displayName: name,
            gender: gender, country: country, birthDate: birthDate, interests: interests,
            avatarData: avatarData, signInMethod: identity.signInMethod, appleUserID: identity.appleUserID))
    }

    func discardPendingIdentity() {
        do {
            try loadLedgerIfNeeded()
            var updated = ledger
            updated.pendingIdentity = nil
            try persist(updated)
            sessionRevision = UUID()
            pendingIdentity = nil
        } catch { showStorageNotice() }
    }

    func signOut() {
        do {
            try loadLedgerIfNeeded()
            var updated = ledger
            updated.activeAccountScope = nil
            updated.pendingIdentity = nil
            try persist(updated)
            sessionRevision = UUID()
            activeProfile = nil
            pendingIdentity = nil
        } catch { showStorageNotice() }
    }

    func updateActiveProfile(displayName: String, country: String) {
        guard var profile = activeProfile else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !region.isEmpty else { return }
        profile.displayName = name
        profile.country = region
        do { try activate(profile) } catch { showStorageNotice() }
    }

    /// Check the real Apple credential on cold launch and foreground return.
    /// Temporary lookup failures do not erase a previously authorized local session.
    func validateAppleSession() async {
        guard ledgerLoaded, !checkingAppleCredential else { return }
        let savedProfile = ledger.activeAccountScope.flatMap { ledger.profiles[$0] }
        guard let userID = savedProfile?.appleUserID ?? ledger.pendingIdentity?.appleUserID else {
            if savedProfile?.signInMethod == "apple" { signOut() }
            return
        }
        checkingAppleCredential = true
        defer { checkingAppleCredential = false }
        let revision = sessionRevision
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
            guard revision == sessionRevision, !Task.isCancelled else { return }
            switch state {
            case .authorized:
                activeProfile = savedProfile
                pendingIdentity = ledger.pendingIdentity
            case .revoked, .notFound, .transferred:
                handleAppleCredentialRevocation()
            @unknown default:
                handleAppleCredentialRevocation()
            }
        } catch {
            guard revision == sessionRevision, !Task.isCancelled else { return }
            sessionNotice = AccountEntryNotice(title: "Apple sign-in couldn't be checked",
                explanation: "Please check your connection and sign in with Apple again. Your saved profile is still on this device.")
        }
    }

    func handleAppleCredentialRevocation() {
        guard activeProfile?.signInMethod == "apple" || pendingIdentity?.signInMethod == "apple"
                || ledger.activeAccountScope.flatMap({ ledger.profiles[$0] })?.signInMethod == "apple"
                || ledger.pendingIdentity?.signInMethod == "apple" else { return }
        signOut()
        // Revocation always closes the visible session, even if protected storage is unavailable.
        sessionRevision = UUID()
        activeProfile = nil
        pendingIdentity = nil
        sessionNotice = AccountEntryNotice(title: "Sign in with Apple again",
            explanation: "Apple access is no longer available. Please authorize Nana again to continue.")
    }

    private func activate(_ profile: NanaAccountProfile) throws {
        var updated = ledger
        updated.profiles[profile.localAccountScope] = profile
        updated.activeAccountScope = profile.localAccountScope
        updated.pendingIdentity = nil
        try persist(updated)
        sessionRevision = UUID()
        activeProfile = profile
        pendingIdentity = nil
    }

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "local-membership.v3"]
    }

    private func loadLedgerIfNeeded() throws {
        guard !ledgerLoaded else { return }
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            // Preserve local profiles created by older app revisions, but do not
            // revive their old active session without going through entry again.
            var migrated = NanaLocalAccountLedger()
            if let data = defaults.data(forKey: "nana.localAccounts.v2"),
               let accounts = try? JSONDecoder().decode([String: NanaAccountProfile].self, from: data) {
                for profile in accounts.values { migrated.profiles[profile.localAccountScope] = profile }
            }
            if let data = defaults.data(forKey: "nana.activeProfile.v1"),
               let profile = try? JSONDecoder().decode(NanaAccountProfile.self, from: data) {
                migrated.profiles[profile.localAccountScope] = profile
            }
            try persist(migrated)
            ["nana.activeProfile.v1", "nana.localAccounts.v2", "nana.pendingIdentity.v1"].forEach { defaults.removeObject(forKey: $0) }
        } else {
            guard status == errSecSuccess, let data = result as? Data,
                  let saved = try? JSONDecoder().decode(NanaLocalAccountLedger.self, from: data) else {
                throw NanaLocalAccountError.storageUnavailable
            }
            ledger = saved
        }
        ledgerLoaded = true
    }

    private func persist(_ updated: NanaLocalAccountLedger) throws {
        guard let data = try? JSONEncoder().encode(updated) else { throw NanaLocalAccountError.storageUnavailable }
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(keychainQuery as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = keychainQuery
            values.forEach { insertion[$0.key] = $0.value }
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NanaLocalAccountError.storageUnavailable }
        ledger = updated
    }

    private func showStorageNotice() {
        sessionNotice = AccountEntryNotice(title: "Couldn't save on this device",
            explanation: NanaLocalAccountError.storageUnavailable.localizedDescription)
    }
}
