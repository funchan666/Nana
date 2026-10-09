import Foundation
import UIKit
import UserNotifications
import Security

struct NanaCredentialSignInRequest: Encodable { let emailAddress: String; let password: String }
struct NanaAppleCredentialExchangeRequest: Encodable { let authorizationCode: String; let identityToken: String; let userIdentifier: String }
struct NanaSessionToken: Decodable { let accessToken: String; let refreshToken: String?; let expiresAt: Date }
struct NanaAuthenticationFailure: Decodable { let code: String; let message: String }

struct NanaLoginMethods {
    let apple: Bool
    let email: Bool
    let visitor: Bool
    let register: Bool
}

struct NanaAuthenticationResult {
    let tokenRequest: [String: Any]
    let message: String
}

@MainActor
final class NanaPushTokenCoordinator: NSObject, UIApplicationDelegate {
    static let shared = NanaPushTokenCoordinator()
    private var latestToken: String?
    private var registrationStarted = false

    func start() {
        guard !registrationStarted else { return }
        registrationStarted = true
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        latestToken = token
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        latestToken = ""
    }

    func waitForCurrentToken(timeout: Duration = .seconds(5)) async -> String {
        if let latestToken { return latestToken }
        let deadline = ContinuousClock.now + timeout
        while latestToken == nil && ContinuousClock.now < deadline {
            guard !Task.isCancelled else { return "" }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return latestToken ?? ""
    }
}

struct NanaDeviceIdentity {
    private let service = "com.nanalantern.harbortide.device"
    private let account = "installation-id"

    func value() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty { return value }
        let value = UUID().uuidString.lowercased()
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let saveStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard saveStatus == errSecSuccess || saveStatus == errSecDuplicateItem else { throw NanaAServiceError.secureStorage }
        return value
    }
}

@MainActor
struct NanaAuthenticationBoundary {
    private let client: NanaAServiceClient
    private let pushTokens: NanaPushTokenCoordinator
    private let deviceIdentity: NanaDeviceIdentity

    init(client: NanaAServiceClient = NanaAServiceClient(), pushTokens: NanaPushTokenCoordinator? = nil, deviceIdentity: NanaDeviceIdentity = NanaDeviceIdentity()) {
        self.client = client
        self.pushTokens = pushTokens ?? NanaPushTokenCoordinator.shared
        self.deviceIdentity = deviceIdentity
    }

    func loginMethods() async throws -> NanaLoginMethods {
        try await client.probeOrigin()
        let (_, object) = try await client.request(path: IntegrationContract.optionsPath, method: "GET")
        guard let code = object[ConfiguredWireFields.code] as? Int, code == 0,
              let data = object[ConfiguredWireFields.data] as? [String: Any] else { throw NanaAServiceError.authenticationUnavailable }
        func flag(_ name: String) -> Bool { (data[name] as? Int) == 1 }
        return NanaLoginMethods(apple: flag(ConfiguredWireFields.apple_lantern), email: flag(ConfiguredWireFields.email_tide), visitor: flag(ConfiguredWireFields.visitor_harbor), register: flag(ConfiguredWireFields.register_current))
    }

    func authenticate(entryMode: String, scene: String, email: String? = nil, password: String? = nil, apple: AppleIdentityResult? = nil, includeEntryContext: Bool = true) async throws -> NanaAuthenticationResult {
        pushTokens.start()
        let pushToken = await pushTokens.waitForCurrentToken()
        var body: [String: Any] = [
            ConfiguredWireFields.release_tag: NanaAServiceConfiguration.clientVersion,
            ConfiguredWireFields.pulse_token: pushToken,
            ConfiguredWireFields.device_fingerprint: try deviceIdentity.value(),
            ConfiguredWireFields.room_delivery_kind: IntegrationContract.continuationMode
        ]
        if includeEntryContext {
            body[ConfiguredWireFields.entry_mode] = entryMode
            body[ConfiguredWireFields.entry_context] = scene
        }
        if let email { body[ConfiguredWireFields.mailbox] = email }
        if let password { body[ConfiguredWireFields.secret_phrase] = password }
        if let apple {
            body[ConfiguredWireFields.apple_subject] = apple.stableIdentity
            if let token = apple.identityToken { body[ConfiguredWireFields.apple_assertion] = token }
            if let code = apple.authorizationCode { body[ConfiguredWireFields.apple_code] = code }
        }
        let (_, object) = try await client.request(path: IntegrationContract.entryPath, method: "POST", body: body)
        guard let code = object[ConfiguredWireFields.code] as? Int, code == 0 else {
            throw NanaAServiceError.authenticationFailed(object[ConfiguredWireFields.message] as? String ?? "Sign-in is unavailable right now.")
        }
        guard let data = object[ConfiguredWireFields.data] as? [String: Any], !data.isEmpty,
              let token = data[ConfiguredWireFields.token] as? [String: Any], !token.isEmpty else {
            throw NanaAServiceError.authenticationFailed("The account service returned no realtime session.")
        }
        do { _ = try ConfiguredRealtimeConfiguration(tokenRequest: token, expectedClientID: IntegrationContract.ablyClientID) }
        catch { throw NanaAServiceError.authenticationFailed("The account service returned an invalid realtime session.") }
        return NanaAuthenticationResult(tokenRequest: token, message: object[ConfiguredWireFields.message] as? String ?? "ok")
    }

    func refresh() async throws -> NanaAuthenticationResult {
        try await authenticate(entryMode: "restore", scene: "silent", includeEntryContext: false)
    }

    func confirmPurchase(transactionID: String, receipt: String, orderCode: String) async throws {
        let body: [String: Any] = [
            ConfiguredWireFields.release_tag: NanaAServiceConfiguration.clientVersion,
            ConfiguredWireFields.device_fingerprint: try deviceIdentity.value(),
            ConfiguredWireFields.store_receipt_id: transactionID,
            ConfiguredWireFields.receipt_blob: receipt,
            ConfiguredWireFields.order_reference: orderCode
        ]
        let (_, object) = try await client.request(path: IntegrationContract.settlementPath, method: "POST", body: body)
        guard let code = object[ConfiguredWireFields.code] as? Int, code == 0 else { throw NanaAServiceError.writeUnavailable }
    }

    func signIn(_ request: NanaCredentialSignInRequest) async throws -> NanaAuthenticationResult {
        try await authenticate(entryMode: "email", scene: "sign-in", email: request.emailAddress, password: request.password)
    }

    func register(_ request: NanaCredentialSignInRequest) async throws -> NanaAuthenticationResult {
        try await authenticate(entryMode: "register", scene: "create-account", email: request.emailAddress, password: request.password)
    }

    func enterAsVisitor() async throws -> NanaAuthenticationResult {
        try await authenticate(entryMode: "visitor", scene: "guest-entry")
    }

    func exchangeAppleCredential(_ request: NanaAppleCredentialExchangeRequest) async throws -> NanaAuthenticationResult {
        let identity = AppleIdentityResult(stableIdentity: request.userIdentifier, emailAddress: nil, displayName: nil, identityToken: request.identityToken, authorizationCode: request.authorizationCode)
        return try await authenticate(entryMode: "apple", scene: "sign-in", apple: identity)
    }

    func logout() async throws { }
}
