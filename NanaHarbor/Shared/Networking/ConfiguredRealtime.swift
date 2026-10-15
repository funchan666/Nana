import Foundation
import CoreFoundation
import UIKit
import Network

enum ConfiguredRealtimeError: LocalizedError {
    case invalidTicket
    case unresolvedPlaceholder
    case invalidConnectionContainer
    case invalidFrame
    case legacyTokenRequest
    case invalidConnectionURL
    case invalidSubscription
    case invalidIdentity
    case invalidExpiry
    case expiredConnection

    var errorDescription: String? {
        switch self {
        case .expiredConnection:
            return "Your sign-in connection has expired. Please try again."
        case .invalidFrame:
            return "The connection was interrupted. Please try again."
        default:
            return "Sign-in is temporarily unavailable. Please try again later."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .invalidTicket: return "invalid_ticket"
        case .unresolvedPlaceholder: return "unresolved_placeholder"
        case .invalidConnectionContainer: return "invalid_connection_container"
        case .invalidFrame: return "invalid_frame"
        case .legacyTokenRequest: return "legacy_token_request"
        case .invalidConnectionURL: return "invalid_connection_url"
        case .invalidSubscription: return "invalid_subscription"
        case .invalidIdentity: return "invalid_identity"
        case .invalidExpiry: return "invalid_expiry"
        case .expiredConnection: return "expired_connection"
        }
    }
}

struct ConfiguredRealtimeTicket {
    let roomID: String?
    let clientID: String?
    let url: URL
    let expiresAt: Date?
    let attachJSON: String
    let channel: String

    static func parseConnectionValue(_ value: Any, now: Date = Date()) throws -> Self {
        let fields: [String: Any]
        if let object = value as? [String: Any] {
            fields = object
        } else if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#{"), trimmed.hasSuffix("}") {
                throw ConfiguredRealtimeError.unresolvedPlaceholder
            }
            guard let bytes = text.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
                throw ConfiguredRealtimeError.invalidConnectionContainer
            }
            fields = object
        } else {
            throw ConfiguredRealtimeError.invalidConnectionContainer
        }
        return try Self(connectionFields: fields, now: now)
    }

    init(connectionFields: [String: Any], now: Date = Date()) throws {
        if let rawURL = connectionFields["url"] as? String, rawURL.contains("#{") {
            throw ConfiguredRealtimeError.unresolvedPlaceholder
        }
        if connectionFields["url"] == nil,
           connectionFields["keyName"] != nil,
           connectionFields["mac"] != nil,
           connectionFields["capability"] != nil {
            throw ConfiguredRealtimeError.legacyTokenRequest
        }
        guard let rawURL = connectionFields["url"] as? String,
              !rawURL.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "wss",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              let url = URL(string: rawURL), url.absoluteString == rawURL else {
            throw ConfiguredRealtimeError.invalidConnectionURL
        }
        guard let attach = connectionFields["attach"] as? [String: Any], !attach.isEmpty,
              Self.integer(attach["action"]) == 10,
              let channel = attach["channel"] as? String,
              !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              JSONSerialization.isValidJSONObject(attach),
              let bytes = try? JSONSerialization.data(withJSONObject: attach),
              let json = String(data: bytes, encoding: .utf8) else {
            throw ConfiguredRealtimeError.invalidSubscription
        }
        guard !json.contains("#{") else {
            throw ConfiguredRealtimeError.unresolvedPlaceholder
        }
        var room: String?
        if let value = connectionFields["roomId"] {
            if let text = value as? String, text.contains("#{") {
                throw ConfiguredRealtimeError.unresolvedPlaceholder
            }
            guard let text = value as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text == channel else {
                throw ConfiguredRealtimeError.invalidIdentity
            }
            room = text
        }
        var client: String?
        if let value = connectionFields["clientId"] {
            guard let text = value as? String, text == IntegrationContract.ablyClientID else {
                throw ConfiguredRealtimeError.invalidIdentity
            }
            client = text
        }
        var expiry: Date?
        if let value = connectionFields["expiresAt"] {
            guard let milliseconds = Self.number(value),
                  milliseconds <= Double(Int64.max) else {
                throw ConfiguredRealtimeError.invalidExpiry
            }
            guard milliseconds / 1000 > now.timeIntervalSince1970 else {
                throw ConfiguredRealtimeError.expiredConnection
            }
            expiry = Date(timeIntervalSince1970: milliseconds / 1000)
        }
        roomID = room
        clientID = client
        self.url = url
        expiresAt = expiry
        attachJSON = json
        self.channel = channel
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func integer(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber,
              !["f", "d"].contains(String(cString: value.objCType)),
              let number = number(value), number.rounded() == number else { return nil }
        return Int(exactly: number)
    }
}

struct ConfiguredRealtimeFrame {
    let action: Int
    let object: [String: Any]

    init(json: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let action = ConfiguredRealtimeTicket.integer(object["action"]) else {
            throw ConfiguredRealtimeError.invalidFrame
        }
        self.action = action
        self.object = object
    }

    var errorCode: Int? {
        let error = object["error"] as? [String: Any]
        return ConfiguredRealtimeTicket.integer(error?["code"])
    }

    var idleTimeoutSeconds: TimeInterval? {
        let details = object["connectionDetails"] as? [String: Any]
        guard let milliseconds = ConfiguredRealtimeTicket.number(details?["maxIdleInterval"]),
              milliseconds > 0, milliseconds <= Double(Int64.max) else { return nil }
        return milliseconds / 1000 + 5
    }

    var messageEntries: [Any]? { object["messages"] as? [Any] }
}

struct ConfiguredRealtimeMessage {
    let id: String?
    let name: String?
    let clientID: String?
    let data: Any?

    init?(_ value: Any, frameID: String?, index: Int) {
        guard let object = value as? [String: Any] else { return nil }
        for key in ["id", "name", "clientId"] {
            if let value = object[key], !(value is NSNull), !(value is String) { return nil }
        }
        if let encoding = object["encoding"], !(encoding is NSNull) {
            guard let text = encoding as? String, ["", "json", "utf8", "utf-8"].contains(text) else { return nil }
        }
        id = object["id"] as? String ?? frameID.map { "\($0):\(index)" }
        name = object["name"] as? String
        clientID = object["clientId"] as? String
        data = object["data"]
    }
}

@MainActor
final class ConfiguredRealtimeTransport {
    enum State { case connecting, connected, subscribed, reconnecting, failed, closed, stopped }
    typealias Refresh = @MainActor () async throws -> ConfiguredRealtimeTicket
    var onMessage: (@MainActor (ConfiguredRealtimeMessage) -> Void)?
    var onState: (@MainActor (State) -> Void)?

    private var ticket: ConfiguredRealtimeTicket?
    private var roomID: String?
    private var refresh: Refresh?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var attachTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var renewalTask: Task<Void, Never>?
    private var renewalID = UUID()
    private var isRefreshing = false
    private var attempt = UUID()
    private var generation = UUID()
    private var running = false
    private var attachStarted = false
    private var ready = false
    private var retryCount = 0
    private var idleInterval: TimeInterval?
    private var lastFrameAt = ProcessInfo.processInfo.systemUptime
    private var connectionDeadline: TimeInterval?
    private var lastRefreshAt: TimeInterval = 0
    private var activeObserver: NSObjectProtocol?
    private var networkMonitor: NWPathMonitor?
    private var networkAvailable: Bool?

    deinit {
        receiveTask?.cancel()
        attachTask?.cancel()
        deadlineTask?.cancel()
        idleTask?.cancel()
        expiryTask?.cancel()
        renewalTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        networkMonitor?.cancel()
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    func start(configuration: ConfiguredRealtimeTicket, refresh: @escaping Refresh) {
        stop()
        running = true
        ticket = configuration
        roomID = configuration.roomID
        self.refresh = refresh
        let currentAttempt = attempt
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.attempt == currentAttempt else { return }
                self.resumeIfNeeded()
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.attempt == currentAttempt, self.running else { return }
                let recovered = self.networkAvailable == false && available
                self.networkAvailable = available
                if recovered { self.resumeIfNeeded() }
            }
        }
        networkMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "com.nanalantern.realtime.network"))
        connect(configuration)
    }

    func stop() {
        running = false
        attempt = UUID()
        cancelRenewal()
        closeSocket()
        networkMonitor?.cancel()
        networkMonitor = nil
        networkAvailable = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        ticket = nil
        roomID = nil
        refresh = nil
        retryCount = 0
        onState?(.stopped)
    }

    private func closeSocket() {
        generation = UUID()
        receiveTask?.cancel(); receiveTask = nil
        attachTask?.cancel(); attachTask = nil
        deadlineTask?.cancel(); deadlineTask = nil
        idleTask?.cancel(); idleTask = nil
        expiryTask?.cancel(); expiryTask = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        attachStarted = false
        ready = false
        idleInterval = nil
        connectionDeadline = nil
    }

    private func cancelRenewal() {
        renewalID = UUID()
        renewalTask?.cancel()
        renewalTask = nil
        isRefreshing = false
    }

    private func connect(_ configuration: ConfiguredRealtimeTicket) {
        guard running else { return }
        closeSocket()
        ticket = configuration
        if let expiry = configuration.expiresAt, expiry <= Date() {
            scheduleRenewal(immediate: false, disconnect: true)
            return
        }
        let id = generation
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        settings.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: settings, delegate: ConfiguredRealtimeRedirectPolicy(), delegateQueue: nil)
        let socket = session.webSocketTask(with: configuration.url)
        self.session = session
        self.socket = socket
        lastFrameAt = ProcessInfo.processInfo.systemUptime
        connectionDeadline = lastFrameAt + 15
        onState?(.connecting)
        guard isCurrent(id) else { return }
        socket.resume()
        receiveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard !Task.isCancelled, self?.isCurrent(id) == true else { return }
                    self?.receive(message, generation: id)
                } catch {
                    guard !Task.isCancelled, self?.isCurrent(id) == true else { return }
                    self?.scheduleRenewal(immediate: false, disconnect: true)
                    return
                }
            }
        }
        deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard !Task.isCancelled, let self, self.isCurrent(id), !self.ready else { return }
            self.scheduleRenewal(immediate: false, disconnect: true)
        }
        if let expiry = configuration.expiresAt {
            let remaining = expiry.timeIntervalSinceNow
            let delay = remaining > 60 ? remaining - 60 : max(1, remaining * 0.8)
            expiryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, let self, self.isCurrent(id) else { return }
                self.scheduleRenewal(immediate: true, disconnect: false)
            }
        }
    }

    private func isCurrent(_ id: UUID) -> Bool { running && generation == id && socket != nil }

    private func receive(_ message: URLSessionWebSocketTask.Message, generation id: UUID) {
        guard isCurrent(id) else { return }
        lastFrameAt = ProcessInfo.processInfo.systemUptime
        armIdleTimer(id)
        let bytes: Data
        switch message {
        case .string(let text): bytes = Data(text.utf8)
        case .data(let data): bytes = data
        @unknown default: return
        }
        guard let frame = try? ConfiguredRealtimeFrame(json: bytes) else {
            debugLog("ignored invalid frame")
            return
        }
        switch frame.action {
        case 4:
            guard !attachStarted else { return }
            guard let idle = frame.idleTimeoutSeconds, let socket, let ticket else {
                scheduleRenewal(immediate: false, disconnect: true)
                return
            }
            idleInterval = idle
            armIdleTimer(id)
            attachStarted = true
            onState?(.connected)
            guard isCurrent(id) else { return }
            attachTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled, self?.isCurrent(id) == true else { return }
                do { try await socket.send(.string(ticket.attachJSON)) }
                catch {
                    guard !Task.isCancelled, self?.isCurrent(id) == true else { return }
                    self?.scheduleRenewal(immediate: false, disconnect: true)
                }
            }
        case 11:
            guard attachStarted, !ready, frame.object["channel"] as? String == ticket?.channel else { return }
            ready = true
            retryCount = 0
            connectionDeadline = nil
            deadlineTask?.cancel(); deadlineTask = nil
            onState?(.subscribed)
        case 15:
            guard attachStarted, frame.object["channel"] as? String == ticket?.channel,
                  let entries = frame.messageEntries else { return }
            let frameID = (frame.object["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            for (index, entry) in entries.enumerated() {
                guard isCurrent(id) else { return }
                guard let message = ConfiguredRealtimeMessage(entry, frameID: frameID, index: index) else {
                    debugLog("ignored invalid message")
                    continue
                }
                onMessage?(message)
            }
        case 9:
            let expired = frame.errorCode.map { (40140...40143).contains($0) } ?? false
            scheduleRenewal(immediate: expired, disconnect: true)
        case 6:
            scheduleRenewal(immediate: false, disconnect: true)
        case 8:
            running = false
            cancelRenewal()
            closeSocket()
            onState?(.closed)
        case 17:
            scheduleRenewal(immediate: true, disconnect: false)
        default: break
        }
    }

    private func armIdleTimer(_ id: UUID) {
        idleTask?.cancel()
        guard let idleInterval else { return }
        let delay = max(0, lastFrameAt + idleInterval - ProcessInfo.processInfo.systemUptime)
        idleTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, self.isCurrent(id) else { return }
            self.scheduleRenewal(immediate: false, disconnect: true)
        }
    }

    private func scheduleRenewal(immediate: Bool, disconnect: Bool, expedite: Bool = false) {
        guard running else { return }
        if disconnect { closeSocket() }
        guard renewalTask == nil else { return }
        guard refresh != nil else {
            running = false
            closeSocket()
            onState?(.failed)
            return
        }
        expiryTask?.cancel(); expiryTask = nil
        let delay = immediate && (retryCount == 0 || expedite) ? 0 : min(30, pow(2, Double(min(retryCount, 5)))) * Double.random(in: 0.8...1.2)
        retryCount = min(retryCount + 1, 6)
        let cooldown = max(0, lastRefreshAt + 1 - ProcessInfo.processInfo.systemUptime)
        let currentAttempt = attempt
        let job = UUID()
        renewalID = job
        onState?(.reconnecting)
        guard running, attempt == currentAttempt else { return }
        renewalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(max(delay, cooldown))) } catch { return }
            guard let provider = self?.refresh,
                  self?.running == true, self?.attempt == currentAttempt, self?.renewalID == job else { return }
            self?.isRefreshing = true
            self?.lastRefreshAt = ProcessInfo.processInfo.systemUptime
            do {
                let renewed = try await provider()
                guard !Task.isCancelled, let self, self.running,
                      self.attempt == currentAttempt, self.renewalID == job else { return }
                if let room = self.roomID, let newRoom = renewed.roomID, room != newRoom {
                    throw ConfiguredRealtimeError.invalidTicket
                }
                guard renewed.channel == self.ticket?.channel else { throw ConfiguredRealtimeError.invalidTicket }
                if self.roomID == nil { self.roomID = renewed.roomID }
                self.renewalTask = nil
                self.isRefreshing = false
                self.connect(renewed)
            } catch {
                guard !Task.isCancelled, let self, self.running,
                      self.attempt == currentAttempt, self.renewalID == job else { return }
                self.renewalTask = nil
                self.isRefreshing = false
                self.scheduleRenewal(immediate: false, disconnect: true)
            }
        }
    }

    private func resumeIfNeeded() {
        guard running, !isRefreshing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let expired = ticket?.expiresAt.map { $0 <= Date() } ?? false
        let idle = idleInterval.map { now >= lastFrameAt + $0 } ?? false
        let overdue = connectionDeadline.map { now >= $0 } ?? false
        guard socket == nil || expired || idle || overdue else { return }
        cancelRenewal()
        scheduleRenewal(immediate: true, disconnect: true, expedite: true)
    }

    private func debugLog(_ reason: String) {
        #if DEBUG
        print("[Realtime] \(reason)")
        #endif
    }
}

private final class ConfiguredRealtimeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
