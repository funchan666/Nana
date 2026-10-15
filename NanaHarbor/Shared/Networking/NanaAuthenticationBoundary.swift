import Foundation
import UIKit
import UserNotifications
import Security

struct NanaCredentialSignInRequest: Encodable { let emailAddress: String; let password: String }
struct NanaAppleCredentialExchangeRequest: Encodable { let authorizationCode: String; let identityToken: String; let userIdentifier: String }
struct NanaSessionToken: Decodable { let accessToken: String; let refreshToken: String?; let expiresAt: Date }
struct NanaAuthenticationFailure: Decodable { let code: String; let message: String }

enum NanaLoginEntryState: Equatable {
    case checking
    case resolved(ConfiguredLoginEntryMode)
    case fallback

    var mode: ConfiguredLoginEntryMode {
        if case .resolved(let mode) = self { return mode }
        return .standard
    }
}

struct NanaAuthenticationResult {
    let realtimeTicket: ConfiguredRealtimeTicket?
    let message: String
}

@MainActor
final class NanaPushTokenCoordinator: NSObject, UIApplicationDelegate {
    static let shared = NanaPushTokenCoordinator()
    private(set) var latestToken: String?
    private var registrationStarted = false
    private var authorizationStarted = false
    private var hasDegraded = false
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]
    private var deadlines: [UUID: DispatchWorkItem] = [:]

    func start() {
        if !registrationStarted {
            registrationStarted = true
            UIApplication.shared.registerForRemoteNotifications()
        }
        guard !authorizationStarted, UIApplication.shared.applicationState == .active else { return }
        authorizationStarted = true
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                if !granted { degrade() }
            } else if settings.authorizationStatus == .denied {
                degrade()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        latestToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        for id in Array(waiters.keys) { complete(id, result: .success(latestToken ?? "")) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        degrade()
    }

    private func degrade() {
        hasDegraded = true
        for id in Array(waiters.keys) { complete(id, result: .success(latestToken ?? "")) }
    }

    private func complete(_ id: UUID, result: Result<String, Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        waiters.removeValue(forKey: id)?.resume(with: result)
    }

    func waitForCurrentToken() async throws -> String {
        start()
        try Task.checkCancellation()
        if let latestToken { return latestToken }
        if hasDegraded { return "" }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                waiters[id] = continuation
                let deadline = DispatchWorkItem { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.complete(id, result: .success(self?.latestToken ?? ""))
                    }
                }
                deadlines[id] = deadline
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(id, result: .failure(CancellationError())) }
        }
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
        guard status == errSecItemNotFound else { throw NanaAServiceError.secureStorage }
        let value = UUID().uuidString.lowercased()
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let saveStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard saveStatus == errSecSuccess || saveStatus == errSecDuplicateItem else { throw NanaAServiceError.secureStorage }
        var saved: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &saved) == errSecSuccess,
              let bytes = saved as? Data, let stored = String(data: bytes, encoding: .utf8), !stored.isEmpty else {
            throw NanaAServiceError.secureStorage
        }
        return stored
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

    private func publicFields(pushToken: String, extras: [String: Any] = [:]) throws -> [String: Any] {
        var body = extras
        body[ConfiguredWireFields.release_tag] = NanaAServiceConfiguration.clientVersion
        body[ConfiguredWireFields.pulse_token] = pushTokens.latestToken ?? pushToken
        body[ConfiguredWireFields.device_fingerprint] = try deviceIdentity.value()
        body[ConfiguredWireFields.room_delivery_kind] = IntegrationContract.continuationMode
        return body
    }

    func loginMethods() async throws -> ConfiguredLoginEntryMode {
        async let probe: Void = client.probeOrigin()
        async let token: String = pushTokens.waitForCurrentToken()
        let (_, readyToken) = try await (probe, token)
        try Task.checkCancellation()
        let body = try publicFields(pushToken: readyToken)
        let (_, object) = try await client.request(path: IntegrationContract.optionsPath, body: body)
        guard NanaAServiceClient.hasSuccessCode(object[ConfiguredWireFields.code]),
              let mode = ConfiguredLoginEntryMode.parse(data: object[ConfiguredWireFields.data]) else {
            throw NanaAServiceError.authenticationUnavailable
        }
        return mode
    }

    func authenticate(entryMode: String, scene: String, email: String? = nil, password: String? = nil, apple: AppleIdentityResult? = nil, includeEntryContext: Bool = true) async throws -> NanaAuthenticationResult {
        pushTokens.start()
        let pushToken = try await pushTokens.waitForCurrentToken()
        try Task.checkCancellation()
        var body: [String: Any] = [:]
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
        body = try publicFields(pushToken: pushToken, extras: body)
        let (response, object) = try await client.request(path: IntegrationContract.entryPath, body: body, allowsAuthenticationResponse: true)
        if let data = object[ConfiguredWireFields.data] as? [String: Any], !data.isEmpty {
            guard let value = data[ConfiguredWireFields.token] else {
                throw NanaAServiceError.authenticationFailed("The account service returned an invalid connection configuration.")
            }
            let ticket: ConfiguredRealtimeTicket
            do { ticket = try ConfiguredRealtimeTicket.parseConnectionValue(value) }
            catch let error as ConfiguredRealtimeError {
                #if DEBUG
                print("[Realtime] configuration rejected: \(error.diagnosticCode)")
                #endif
                throw NanaAServiceError.authenticationFailed(error.localizedDescription)
            }
            catch { throw NanaAServiceError.authenticationFailed("The account service returned an invalid connection configuration.") }
            return NanaAuthenticationResult(realtimeTicket: ticket, message: object[ConfiguredWireFields.message] as? String ?? "ok")
        }
        let rawData = object[ConfiguredWireFields.data]
        guard rawData == nil || rawData is NSNull || (rawData as? [String: Any])?.isEmpty == true,
              (200..<300).contains(response.statusCode), NanaAServiceClient.hasSuccessCode(object[ConfiguredWireFields.code]) else {
            throw NanaAServiceError.authenticationFailed(object[ConfiguredWireFields.message] as? String ?? "Sign-in is unavailable right now.")
        }
        return NanaAuthenticationResult(realtimeTicket: nil, message: object[ConfiguredWireFields.message] as? String ?? "ok")
    }

    func refresh() async throws -> NanaAuthenticationResult {
        try await authenticate(entryMode: "restore", scene: "silent", includeEntryContext: false)
    }

    func confirmPurchase(transactionID: String, receipt: String, confirmation: NanaPurchaseConfirmation, version: String, deviceID: String) async throws {
        guard let origin = URL(string: confirmation.origin), origin.scheme == "https", origin.host != nil else {
            throw NanaAServiceError.invalidResponse
        }
        let body: [String: Any] = [
            confirmation.versionField: version,
            confirmation.deviceField: deviceID,
            confirmation.transactionField: transactionID,
            confirmation.receiptField: receipt,
            confirmation.orderField: confirmation.orderCode
        ]
        guard body.count == 5 else { throw NanaAServiceError.invalidResponse }
        let (_, object) = try await NanaAServiceClient(baseURL: origin).request(path: confirmation.path, body: body)
        guard NanaAServiceClient.hasSuccessCode(object[confirmation.successField]) else { throw NanaAServiceError.writeUnavailable }
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
