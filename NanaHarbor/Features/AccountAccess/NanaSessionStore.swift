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
    var introduction: String? = nil

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
    var appleIntroductions: [String: NanaPendingIdentity] = [:]
}

enum NanaSignedOutDestination: Equatable { case welcome, login }

struct NanaAccountExitProgress {
    let title: String
    let detail: String
    let isWorking: Bool
}

enum NanaLocalAccountError: LocalizedError {
    case invalidEntry, missingIdentity, incompleteProfile, visitorUnavailable, storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidEntry: return "Enter a valid email address and a password of 8–128 characters."
        case .missingIdentity: return "Please return to sign-in and start again."
        case .incompleteProfile: return "Add your name, gender, country, date of birth and at least one tag."
        case .visitorUnavailable: return "Guest access is not available right now. Please choose another sign-in method."
        case .storageUnavailable: return "Nana couldn't save your details. Please try again."
        }
    }
}

@MainActor
final class NanaSessionStore: ObservableObject {
    @Published private(set) var activeProfile: NanaAccountProfile?
    @Published private(set) var pendingIdentity: NanaPendingIdentity?
    @Published var sessionNotice: AccountEntryNotice?
    @Published private(set) var suggestedSignInEmail = ""
    @Published private(set) var signedOutDestination: NanaSignedOutDestination = .welcome
    @Published private(set) var accountExitProgress: NanaAccountExitProgress?
    @Published private(set) var loginMethods = NanaLoginMethods(apple: false, email: false, visitor: false, register: false)
    @Published private(set) var isEntryInProgress = false
    private(set) var entryGeneration = UUID()
    @Published private(set) var entryScreenRevision = UUID()
    private(set) var remoteTokenRequest: [String: Any]?

    private let authentication: NanaAuthenticationBoundary

    var savedProfiles: [NanaAccountProfile] {
        ledger.profiles.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func startAccountEntry(emailAddress: String = "") {
        signOut(destination: emailAddress.isEmpty ? .welcome : .login)
        guard activeProfile == nil else { return }
        suggestedSignInEmail = emailAddress
    }

    private let defaults: UserDefaults
    private let keychainService = "com.nanalantern.harbortide.local-accounts"
    private var ledger = NanaLocalAccountLedger()
    private var ledgerLoaded = false
    private var sessionRevision = UUID()
    private var checkingAppleCredential = false

    init(defaults: UserDefaults = .standard, authentication: NanaAuthenticationBoundary? = nil) {
        self.defaults = defaults
        self.authentication = authentication ?? NanaAuthenticationBoundary()
    }

    var isSignedIn: Bool { activeProfile != nil }

    func beginEntryAttempt() throws -> UUID {
        guard !isEntryInProgress else { throw CancellationError() }
        entryGeneration = UUID()
        isEntryInProgress = true
        return entryGeneration
    }

    func checkEntryAttempt(_ attempt: UUID) throws {
        try Task.checkCancellation()
        guard entryGeneration == attempt else { throw CancellationError() }
    }

    func resumeEntryPreparation() {
        isEntryInProgress = true
    }

    func finishEntryPreparation() {
        isEntryInProgress = false
    }

    func cancelEntryAttempt(_ attempt: UUID) {
        guard entryGeneration == attempt else { return }
        entryGeneration = UUID()
        isEntryInProgress = false
    }

    func restoreLocalSession() async {
        guard let attempt = try? beginEntryAttempt() else { return }
        defer { if entryGeneration == attempt && activeProfile == nil { finishEntryPreparation() } }
        do {
            try loadLedgerIfNeeded()
            let profile = ledger.activeAccountScope.flatMap { ledger.profiles[$0] }
            if let profile {
                let result = try await authentication.refresh()
                try checkEntryAttempt(attempt)
                remoteTokenRequest = result.tokenRequest
                activeProfile = profile
            }
            await validateAppleSession()
        } catch {
            guard entryGeneration == attempt else { return }
            activeProfile = nil
            remoteTokenRequest = nil
        }
    }

    func loadLoginMethods() async {
        do { loginMethods = try await authentication.loginMethods() }
        catch { loginMethods = NanaLoginMethods(apple: true, email: true, visitor: false, register: true) }
    }

    func refreshRealtimeToken(completion: @escaping (Result<ConfiguredRealtimeConfiguration, Error>) -> Void) {
        let revision = entryGeneration
        let scope = activeProfile?.localAccountScope
        Task { @MainActor in
            do {
                let result = try await authentication.refresh()
                guard revision == entryGeneration, let scope, activeProfile?.localAccountScope == scope, !Task.isCancelled else { throw CancellationError() }
                guard let token = result.tokenRequest else { throw NanaAServiceError.authenticationUnavailable }
                let configuration = try ConfiguredRealtimeConfiguration(tokenRequest: token, expectedClientID: IntegrationContract.ablyClientID)
                remoteTokenRequest = token
                completion(.success(configuration))
            } catch { completion(.failure(error)) }
        }
    }

    private func authenticateForAttempt(_ attempt: UUID, operation: () async throws -> NanaAuthenticationResult) async throws -> NanaAuthenticationResult {
        do {
            let result = try await operation()
            try checkEntryAttempt(attempt)
            return result
        } catch {
            try checkEntryAttempt(attempt)
            throw error
        }
    }

    func signIn(emailAddress: String, password: String) async throws {
        let attempt = try beginEntryAttempt()
        defer { if entryGeneration == attempt && activeProfile == nil { finishEntryPreparation() } }
        let entry = AccountEntryDraft(emailAddress: emailAddress, accountPassword: password)
        guard entry.validationMessage(for: .signIn) == nil else { throw NanaLocalAccountError.invalidEntry }
        let email = entry.normalizedEmailAddress
        let result = try await authenticateForAttempt(attempt) { try await authentication.signIn(NanaCredentialSignInRequest(emailAddress: email, password: password)) }
        try checkEntryAttempt(attempt)
        remoteTokenRequest = result.tokenRequest
        try loadLedgerIfNeeded()
        let scope = "email.\(email)"
        let profile = ledger.profiles[scope] ?? NanaAccountProfile(emailAddress: email, displayName: "Nana member", gender: "", country: "", birthDate: nil, interests: [], avatarData: nil, signInMethod: "password", appleUserID: nil)
        try activate(profile)
    }

    func signInAsVisitor() async throws {
        let attempt = try beginEntryAttempt()
        defer { if entryGeneration == attempt && activeProfile == nil { finishEntryPreparation() } }
        guard loginMethods.visitor else { throw NanaLocalAccountError.visitorUnavailable }
        let result = try await authenticateForAttempt(attempt) { try await authentication.enterAsVisitor() }
        try checkEntryAttempt(attempt)
        remoteTokenRequest = result.tokenRequest
        try loadLedgerIfNeeded()
        let visitorEmail = "visitor.\(UUID().uuidString.lowercased())@nana.local"
        let profile = NanaAccountProfile(emailAddress: visitorEmail, displayName: "Guest", gender: "", country: "", birthDate: nil,
            interests: [], avatarData: nil, signInMethod: "visitor", appleUserID: nil)
        try activate(profile)
    }

    func preparePasswordRegistration(emailAddress: String, password: String) async throws {
        let attempt = try beginEntryAttempt()
        defer { if entryGeneration == attempt && activeProfile == nil { finishEntryPreparation() } }
        let entry = AccountEntryDraft(emailAddress: emailAddress, accountPassword: password)
        guard entry.validationMessage(for: .createAccount) == nil else { throw NanaLocalAccountError.invalidEntry }
        let result = try await authenticateForAttempt(attempt) { try await authentication.register(NanaCredentialSignInRequest(emailAddress: entry.normalizedEmailAddress, password: password)) }
        try checkEntryAttempt(attempt)
        remoteTokenRequest = result.tokenRequest
        try loadLedgerIfNeeded()
        var updated = ledger
        updated.pendingIdentity = NanaPendingIdentity(emailAddress: entry.normalizedEmailAddress, displayName: ledger.profiles["email.\(entry.normalizedEmailAddress)"]?.displayName ?? "", signInMethod: "password", appleUserID: nil)
        try persist(updated)
        sessionRevision = UUID()
        pendingIdentity = updated.pendingIdentity
    }

    func acceptAppleAuthorization(_ identity: AppleIdentityResult, attempt: UUID) async throws -> Bool {
        try checkEntryAttempt(attempt)
        defer { if entryGeneration == attempt && activeProfile == nil { finishEntryPreparation() } }
        guard !identity.stableIdentity.isEmpty else { throw NanaLocalAccountError.missingIdentity }
        let result = try await authenticateForAttempt(attempt) { try await authentication.exchangeAppleCredential(NanaAppleCredentialExchangeRequest(authorizationCode: identity.authorizationCode ?? "", identityToken: identity.identityToken ?? "", userIdentifier: identity.stableIdentity)) }
        try checkEntryAttempt(attempt)
        remoteTokenRequest = result.tokenRequest
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
        resumeEntryPreparation()
    }

    func discardPendingIdentity() {
        entryGeneration = UUID()
        isEntryInProgress = false
        remoteTokenRequest = nil
        do {
            try loadLedgerIfNeeded()
            var updated = ledger
            updated.pendingIdentity = nil
            try persist(updated)
            sessionRevision = UUID()
            pendingIdentity = nil
        } catch { showStorageNotice() }
    }

    @discardableResult
    func signOut(destination: NanaSignedOutDestination = .welcome) -> Bool {
        entryGeneration = UUID()
        isEntryInProgress = false
        defer {
            ledger.activeAccountScope = nil
            ledger.pendingIdentity = nil
            entryScreenRevision = UUID()
            sessionRevision = UUID()
            suggestedSignInEmail = ""
            signedOutDestination = destination
            activeProfile = nil
            pendingIdentity = nil
            remoteTokenRequest = nil
        }
        do {
            try loadLedgerIfNeeded()
            var updated = ledger
            updated.activeAccountScope = nil
            updated.pendingIdentity = nil
            try persist(updated)
            return true
        } catch { showStorageNotice(); return false }
    }

    func exitAccount(deleting: Bool, contentStore: NanaContentStore, coinStore: NanaCoinStore) async {
        guard accountExitProgress == nil, let profile = activeProfile else { return }
        guard !coinStore.isPresentingPurchase else {
            sessionNotice = AccountEntryNotice(title: "Purchase in progress", explanation: "Wait for the current purchase to finish before leaving this account.")
            return
        }
        let scope = profile.localAccountScope
        accountExitProgress = NanaAccountExitProgress(title: deleting ? "Deleting local account…" : "Logging out…",
            detail: deleting ? "Removing this account’s data from this device." : "Keeping your saved details for next time.", isWorking: true)
        try? await Task.sleep(for: .milliseconds(300))
        guard activeProfile?.localAccountScope == scope else { accountExitProgress = nil; return }
        do {
            try loadLedgerIfNeeded()
            var updated = ledger
            updated.activeAccountScope = nil
            updated.pendingIdentity = nil
            if deleting {
                try contentStore.deleteLocalAccountData(accountID: scope)
                try coinStore.deleteLocalAccountData(accountID: scope)
                let avatar = try avatarURL(for: scope)
                if FileManager.default.fileExists(atPath: avatar.path) { try FileManager.default.removeItem(at: avatar) }
                updated.profiles.removeValue(forKey: scope)
                if let appleID = profile.appleUserID { updated.appleIntroductions.removeValue(forKey: appleID) }
            }
            try persist(updated)
            sessionRevision = UUID()
            try? await NanaCheckInReminder.configure(enabled: false)
            accountExitProgress = NanaAccountExitProgress(title: deleting ? "Local account deleted" : "Logged out successfully",
                detail: "Returning to welcome…", isWorking: false)
            try? await Task.sleep(for: .milliseconds(1000))
            suggestedSignInEmail = ""
            signedOutDestination = .welcome
            pendingIdentity = nil
            remoteTokenRequest = nil
            entryGeneration = UUID()
            entryScreenRevision = UUID()
            isEntryInProgress = false
            activeProfile = nil
            accountExitProgress = nil
        } catch {
            accountExitProgress = nil
            sessionNotice = AccountEntryNotice(title: deleting ? "Deletion did not complete" : "Couldn’t log out",
                explanation: deleting ? "Some local data may already have been removed. Please retry to finish deleting this account." : "Your session is still open. Please try again.")
        }
    }

    @discardableResult
    func updateActiveProfile(displayName: String, country: String, avatarData: Data? = nil, accountScope: String,
                             gender: String? = nil, birthDate: Date? = nil, interests: [String]? = nil,
                             introduction: String? = nil, resetAvatar: Bool = false) -> Bool {
        guard var profile = activeProfile, profile.localAccountScope == accountScope else { return false }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        profile.displayName = name
        profile.country = region
        if resetAvatar { profile.avatarData = nil }
        else if let avatarData { profile.avatarData = avatarData }
        if let gender { profile.gender = gender }
        if let birthDate { profile.birthDate = birthDate }
        if let interests { profile.interests = interests }
        if let introduction { profile.introduction = String(introduction.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)) }
        do {
            try activate(profile)
            return true
        } catch {
            showStorageNotice()
            return false
        }
    }

    @discardableResult
    func validateAppleSession() async -> Bool {
        guard ledgerLoaded, !checkingAppleCredential, accountExitProgress == nil else { return false }
        let savedProfile = ledger.activeAccountScope.flatMap { ledger.profiles[$0] }
        guard let userID = savedProfile?.appleUserID ?? ledger.pendingIdentity?.appleUserID else {
            if savedProfile?.signInMethod == "apple" { signOut() }
            return false
        }
        checkingAppleCredential = true
        defer { checkingAppleCredential = false }
        let revision = sessionRevision
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
            guard revision == sessionRevision, !Task.isCancelled else { return false }
            switch state {
            case .authorized:
                activeProfile = savedProfile
                pendingIdentity = ledger.pendingIdentity
                return true
            case .revoked, .notFound, .transferred:
                handleAppleCredentialRevocation()
            @unknown default:
                handleAppleCredentialRevocation()
            }
        } catch {
            guard revision == sessionRevision, !Task.isCancelled else { return false }
            sessionNotice = AccountEntryNotice(title: "Apple sign-in couldn't be checked",
                explanation: "Please check your connection and sign in with Apple again.")
        }
        return false
    }

    func handleAppleCredentialRevocation() {
        guard activeProfile?.signInMethod == "apple" || pendingIdentity?.signInMethod == "apple"
                || ledger.activeAccountScope.flatMap({ ledger.profiles[$0] })?.signInMethod == "apple"
                || ledger.pendingIdentity?.signInMethod == "apple" else { return }
        signOut()
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
        suggestedSignInEmail = ""
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
            ledger.profiles = ledger.profiles.reduce(into: [String: NanaAccountProfile]()) { result, item in
                let (scope, profile) = item
                var hydrated = profile
                hydrated.avatarData = try? loadAvatar(for: scope)
                result[scope] = hydrated
            }
        }
        ledgerLoaded = true
    }

    private func persist(_ updated: NanaLocalAccountLedger) throws {
        var secureLedger = updated
        secureLedger.profiles = updated.profiles.mapValues { profile in
            var profileWithoutPhoto = profile
            profileWithoutPhoto.avatarData = nil
            return profileWithoutPhoto
        }
        guard let data = try? JSONEncoder().encode(secureLedger) else { throw NanaLocalAccountError.storageUnavailable }
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(keychainQuery as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = keychainQuery
            values.forEach { insertion[$0.key] = $0.value }
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NanaLocalAccountError.storageUnavailable }
        for (scope, profile) in updated.profiles {
            if let avatarData = profile.avatarData {
                try saveAvatar(avatarData, for: scope)
            } else {
                try? removeAvatar(for: scope)
            }
        }
        ledger = updated
    }

    private func avatarDirectory() throws -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NanaLocalAccountError.storageUnavailable
        }
        var directory = root.appendingPathComponent("NanaLocalProfileMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }

    private func avatarURL(for scope: String) throws -> URL {
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return try avatarDirectory().appendingPathComponent(digest).appendingPathExtension("jpg")
    }

    private func saveAvatar(_ data: Data, for scope: String) throws {
        let url = try avatarURL(for: scope)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func loadAvatar(for scope: String) throws -> Data {
        try Data(contentsOf: avatarURL(for: scope))
    }

    private func removeAvatar(for scope: String) throws {
        try FileManager.default.removeItem(at: avatarURL(for: scope))
    }

    private func showStorageNotice() {
        sessionNotice = AccountEntryNotice(title: "Couldn't save your details",
            explanation: NanaLocalAccountError.storageUnavailable.localizedDescription)
    }
}
