import Foundation
import Combine
import Security

struct NanaAccountProfile: Codable, Equatable {
    let emailAddress: String
    var displayName: String
    var gender: String
    var country: String
    var birthDate: Date
    var interests: [String]
    var avatarData: Data?
    let signInMethod: String
}

struct NanaPendingIdentity {
    let emailAddress: String
    let displayName: String
    let signInMethod: String
}

@MainActor
final class NanaSessionStore: ObservableObject {
    @Published private(set) var activeProfile: NanaAccountProfile?
    @Published private(set) var pendingIdentity: NanaPendingIdentity?
    @Published private(set) var onboardingFinished: Bool

    private let defaults: UserDefaults
    private let profileKey = "nana.activeProfile.v1"
    private let pendingKey = "nana.pendingIdentity.v1"
    private let onboardingKey = "nana.onboardingFinished.v1"
    private let keychainService = "com.nana.harbor.credentials"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.onboardingFinished = defaults.bool(forKey: onboardingKey)
        if let data = defaults.data(forKey: profileKey) {
            activeProfile = try? JSONDecoder().decode(NanaAccountProfile.self, from: data)
        }
        if let data = defaults.data(forKey: pendingKey) {
            pendingIdentity = try? JSONDecoder().decode(PersistedPendingIdentity.self, from: data).identity
        }
    }

    var isSignedIn: Bool { activeProfile != nil }

    func finishOnboarding() {
        onboardingFinished = true
        defaults.set(true, forKey: onboardingKey)
    }

    func preparePasswordRegistration(emailAddress: String, password: String) {
        let normalized = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        savePassword(password, for: normalized)
        setPendingIdentity(NanaPendingIdentity(emailAddress: normalized, displayName: "", signInMethod: "password"))
    }

    func prepareAppleRegistration(emailAddress: String?, displayName: String?, stableIdentity: String) {
        let normalizedEmail = (emailAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        saveAppleIdentity(stableIdentity, for: normalizedEmail)
        setPendingIdentity(NanaPendingIdentity(
            emailAddress: normalizedEmail,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            signInMethod: "apple"
        ))
    }

    func signIn(emailAddress: String, password: String) -> Bool {
        let normalized = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let profile = storedProfile(for: normalized),
              profile.signInMethod == "password",
              loadPassword(for: normalized) == password else { return false }
        activeProfile = profile
        persistProfile(profile)
        return true
    }

    func discardPendingIdentity() {
        pendingIdentity = nil
        defaults.removeObject(forKey: pendingKey)
    }

    func completeProfile(displayName: String, gender: String, country: String, birthDate: Date, interests: [String], avatarData: Data?) {
        guard let identity = pendingIdentity else { return }
        let profile = NanaAccountProfile(
            emailAddress: identity.emailAddress,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: gender,
            country: country,
            birthDate: birthDate,
            interests: interests,
            avatarData: avatarData,
            signInMethod: identity.signInMethod
        )
        activeProfile = profile
        persistProfile(profile)
        defaults.removeObject(forKey: pendingKey)
        pendingIdentity = nil
    }

    func signOut() {
        activeProfile = nil
        defaults.removeObject(forKey: profileKey)
    }

    func updateActiveProfile(displayName: String, country: String) {
        guard var profile = activeProfile else { return }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCountry.isEmpty else { return }
        profile.displayName = trimmedName
        profile.country = trimmedCountry
        activeProfile = profile
        persistProfile(profile)
    }

    private func setPendingIdentity(_ identity: NanaPendingIdentity) {
        pendingIdentity = identity
        let persisted = PersistedPendingIdentity(identity: identity)
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: pendingKey)
        }
    }

    private func persistProfile(_ profile: NanaAccountProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: profileKey)
        }
    }

    private func storedProfile(for emailAddress: String) -> NanaAccountProfile? {
        guard let data = defaults.data(forKey: profileKey),
              let profile = try? JSONDecoder().decode(NanaAccountProfile.self, from: data),
              profile.emailAddress == emailAddress else { return nil }
        return profile
    }

    private func savePassword(_ password: String, for account: String) {
        saveKeychain(Data(password.utf8), account: "password.\(account)")
    }

    private func loadPassword(for account: String) -> String? {
        guard let data = loadKeychain(account: "password.\(account)") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveAppleIdentity(_ identity: String, for account: String) {
        saveKeychain(Data(identity.utf8), account: "apple.\(account)")
    }

    private func saveKeychain(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var value = query
        value[kSecValueData as String] = data
        SecItemAdd(value as CFDictionary, nil)
    }

    private func loadKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private struct PersistedPendingIdentity: Codable {
        let emailAddress: String
        let displayName: String
        let signInMethod: String

        init(identity: NanaPendingIdentity) {
            emailAddress = identity.emailAddress
            displayName = identity.displayName
            signInMethod = identity.signInMethod
        }

        var identity: NanaPendingIdentity {
            NanaPendingIdentity(emailAddress: emailAddress, displayName: displayName, signInMethod: signInMethod)
        }
    }
}
