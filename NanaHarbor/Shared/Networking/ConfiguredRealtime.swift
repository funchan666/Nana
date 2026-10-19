import Foundation
import CoreFoundation
import Network
import UIKit
import OSLog

enum ConfiguredRealtimeError: String, Error, LocalizedError {
    case unresolvedPlaceholder, invalidFieldMapping, invalidConnectionContainer, legacyTokenRequest
    case invalidConnectionURL, invalidSubscription, invalidIdentity, invalidExpiry
    case expiredConnection, invalidFrame, invalidMessage, unsupportedEncoding
    case invalidAcknowledgement, serialExhausted, notReady, capacityExceeded
    case sendFailed, acknowledgementFailed, acknowledgementSkipped, acknowledgementTimeout
    case connectionReplaced, connectionTimeout, attemptTimeout, refreshFailed, refreshTimeout
    case disconnected, detached, idleTimeout, serverClosed, serverRejected, stopped
    var errorDescription: String? {
        switch self {
        case .expiredConnection: return "The sign-in connection expired. Please try again."
        case .notReady: return "The connection is not ready. Please try again."
        default: return "The connection is temporarily unavailable. Please try again."
        }
    }
}

enum ConfiguredRealtimeJSON {
    static let maximumBytes = 1_048_576
    static func object(_ value: Any) throws -> [String: Any] {
        if let object = value as? [String: Any] { return object }
        guard let text = value as? String else { throw ConfiguredRealtimeError.invalidConnectionContainer }
        if text.contains("#{") { throw ConfiguredRealtimeError.unresolvedPlaceholder }
        guard let data = text.data(using: .utf8), data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfiguredRealtimeError.invalidConnectionContainer
        }
        return object
    }
    static func integer(_ value: Any?) -> Int64? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let type = String(cString: value.objCType)
        guard ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(type) else { return nil }
        return Int64(value.stringValue)
    }
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    static func optionalString(_ value: Any?) throws -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw ConfiguredRealtimeError.invalidMessage }
        return text.isEmpty ? nil : text
    }
    static func text(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let bytes = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              bytes.count <= maximumBytes, let text = String(data: bytes, encoding: .utf8) else {
            throw ConfiguredRealtimeError.invalidFrame
        }
        return text
    }
}

struct ConfiguredRealtimeFieldNames: Sendable {
    let url: String
    let attach: String
    let action: String
    let channel: String
    let expiresAt: String?
    let roomID: String?
    let clientID: String?

    init(url: String, attach: String, action: String, channel: String, expiresAt: String? = nil, roomID: String? = nil, clientID: String? = nil) {
        self.roomID = roomID; self.clientID = clientID
        self.url = url; self.attach = attach; self.action = action; self.channel = channel; self.expiresAt = expiresAt
    }
    fileprivate static let reserved: Set<String> = [
        "token", "url", "attach", "action", "channel", "roomId", "clientId", "expiresAt",
        "keyName", "nonce", "mac", "ttl", "capability", "timestamp"
    ]
    fileprivate func validate() throws {
        let names = [url, attach, action, channel] + [expiresAt, roomID, clientID].compactMap { $0 }
        guard Set(names).count == names.count,
              names.allSatisfy({ $0.range(of: #"\A[A-Za-z_][A-Za-z0-9_.-]*\z"#, options: .regularExpression) != nil }) else { throw ConfiguredRealtimeError.invalidFieldMapping }
    }
}

struct ConfiguredRealtimeTicket {
    let url: URL
    let channel: String
    let expectedClientID: String
    let expiresAt: Date?
    let attachJSON: String

    static func parseConnectionValue(_ value: Any, fields: ConfiguredRealtimeFieldNames,
                                     expectedClientID: String, now: Date = Date()) throws -> Self {
        try fields.validate()
        let connection = try ConfiguredRealtimeJSON.object(value)
        if connection["keyName"] != nil, connection["mac"] != nil {
            throw ConfiguredRealtimeError.legacyTokenRequest
        }
        let allowed = Set([fields.url, fields.attach] + [fields.expiresAt, fields.roomID, fields.clientID].compactMap { $0 })
        guard Set(connection.keys).isSubset(of: allowed) else { throw ConfiguredRealtimeError.invalidConnectionContainer }
        guard !expectedClientID.isEmpty else { throw ConfiguredRealtimeError.invalidIdentity }
        if let text = connection[fields.url] as? String, text.contains("#{") {
            throw ConfiguredRealtimeError.unresolvedPlaceholder
        }
        guard let text = connection[fields.url] as? String, !text.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: text), parts.scheme?.lowercased() == "wss",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, let url = URL(string: text), url.absoluteString == text else {
            throw ConfiguredRealtimeError.invalidConnectionURL
        }
        guard let attach = connection[fields.attach] as? [String: Any],
              Set(attach.keys).subtracting([fields.action, fields.channel]).isDisjoint(with: ConfiguredRealtimeFieldNames.reserved),
              ConfiguredRealtimeJSON.integer(attach[fields.action]) == 10,
              let channel = attach[fields.channel] as? String,
              !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfiguredRealtimeError.invalidSubscription
        }
        if let key = fields.roomID, let value = connection[key], (value as? String) != channel {
            throw ConfiguredRealtimeError.invalidIdentity
        }
        if let key = fields.clientID, let value = connection[key], (value as? String) != expectedClientID {
            throw ConfiguredRealtimeError.invalidIdentity
        }
        var protocolAttach = attach
        protocolAttach.removeValue(forKey: fields.action)
        protocolAttach.removeValue(forKey: fields.channel)
        protocolAttach["action"] = 10
        protocolAttach["channel"] = channel
        let attachJSON = try ConfiguredRealtimeJSON.text(protocolAttach)
        guard !attachJSON.contains("#{") else { throw ConfiguredRealtimeError.unresolvedPlaceholder }
        var expiry: Date?
        if let key = fields.expiresAt, let rawExpiry = connection[key] {
            guard let milliseconds = ConfiguredRealtimeJSON.integer(rawExpiry), milliseconds > 0,
                  milliseconds < 253_402_300_800_000 else { throw ConfiguredRealtimeError.invalidExpiry }
            let seconds = Double(milliseconds) / 1000
            guard seconds > now.timeIntervalSince1970 else { throw ConfiguredRealtimeError.expiredConnection }
            expiry = Date(timeIntervalSince1970: seconds)
        }
        return Self(url: url, channel: channel, expectedClientID: expectedClientID,
                    expiresAt: expiry, attachJSON: attachJSON)
    }
}

struct ConfiguredRealtimeFrame {
    let action: Int64
    let object: [String: Any]
    init(json: Data) throws {
        guard json.count <= ConfiguredRealtimeJSON.maximumBytes,
              let fields = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let action = ConfiguredRealtimeJSON.integer(fields["action"]), action >= 0 else {
            throw ConfiguredRealtimeError.invalidFrame
        }
        self.action = action
        object = fields
    }
    var channel: String? { object["channel"] as? String }
    var errorCode: Int64? { ConfiguredRealtimeJSON.integer((object["error"] as? [String: Any])?["code"]) }
    var credentialRejected: Bool { errorCode.map { (40140...40149).contains($0) } ?? false }
    var idleTimeout: TimeInterval? {
        guard let details = object["connectionDetails"] as? [String: Any],
              let milliseconds = ConfiguredRealtimeJSON.number(details["maxIdleInterval"]),
              milliseconds > 0, milliseconds <= 86_400_000 else { return nil }
        return milliseconds / 1000 + 5
    }
}

struct ConfiguredRealtimeMessage {
    let name: String?
    let data: Any
    let id: String?
    let clientID: String?
    let channel: String

    static func parse(_ value: Any, channel: String, protocolID: String? = nil, index: Int = 0) throws -> Self {
        guard let fields = value as? [String: Any] else { throw ConfiguredRealtimeError.invalidMessage }
        let name = try ConfiguredRealtimeJSON.optionalString(fields["name"])
        let ownID = try ConfiguredRealtimeJSON.optionalString(fields["id"])
        let id = ownID ?? protocolID.flatMap { $0.isEmpty ? nil : "\($0):\(index)" }
        let client = try ConfiguredRealtimeJSON.optionalString(fields["clientId"])
        let encoding = try ConfiguredRealtimeJSON.optionalString(fields["encoding"])
        var data: Any = fields["data"] ?? NSNull()
        if let encoding = encoding, !["json", "utf-8", "utf8"].contains(encoding) {
            throw ConfiguredRealtimeError.unsupportedEncoding
        }
        if encoding == "json" {
            guard let text = data as? String, let bytes = text.data(using: .utf8),
                  bytes.count <= ConfiguredRealtimeJSON.maximumBytes,
                  let decoded = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) else {
                throw ConfiguredRealtimeError.invalidMessage
            }
            data = decoded
        }
        return Self(name: name, data: data, id: id, clientID: client, channel: channel)
    }
}

struct ConfiguredRealtimeACKLedger {
    private(set) var nextSerial: Int64 = 0
    private(set) var pending: Set<Int64> = []
    mutating func reserve() throws -> Int64 {
        guard nextSerial < Int64.max else { throw ConfiguredRealtimeError.serialExhausted }
        let serial = nextSerial
        nextSerial += 1
        pending.insert(serial)
        return serial
    }
    mutating func remove(_ serial: Int64) -> Bool { pending.remove(serial) != nil }
    mutating func drain() -> [Int64] { let values = pending.sorted(); pending.removeAll(); return values }
    mutating func apply(_ frame: ConfiguredRealtimeFrame) throws -> (confirmed: [Int64], skipped: [Int64]) {
        guard frame.action == 1 || frame.action == 2 else { throw ConfiguredRealtimeError.invalidAcknowledgement }
        func integerOrZero(_ key: String) throws -> Int64 {
            guard let value = frame.object[key], !(value is NSNull) else { return 0 }
            guard let integer = ConfiguredRealtimeJSON.integer(value), integer >= 0 else {
                throw ConfiguredRealtimeError.invalidAcknowledgement
            }
            return integer
        }
        let start = try integerOrZero("msgSerial"), count = try integerOrZero("count")
        let (end, overflow) = start.addingReportingOverflow(count)
        guard !overflow, end <= nextSerial else { throw ConfiguredRealtimeError.invalidAcknowledgement }
        guard count > 0 else { return ([], []) }
        let skipped = pending.filter { $0 < start }.sorted()
        let confirmed = pending.filter { $0 >= start && $0 < end }.sorted()
        for serial in skipped + confirmed { pending.remove(serial) }
        return (confirmed, skipped)
    }
}

protocol ConfiguredRealtimeSocket: AnyObject, Sendable {
    func resume()
    func receive(_ completion: @escaping @Sendable (Result<Data, Error>) -> Void)
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void)
    func cancel()
}

@available(iOS 13.0, macOS 10.15, *)
private final class ConfiguredURLSessionSocket: NSObject, ConfiguredRealtimeSocket, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!
    init(url: URL) {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = ConfiguredRealtimeJSON.maximumBytes
    }
    func resume() { task.resume() }
    func receive(_ completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        task.receive { result in
            completion(result.flatMap { message in
                switch message {
                case .data(let data): return .success(data)
                case .string(let text): return .success(Data(text.utf8))
                @unknown default: return .failure(ConfiguredRealtimeError.invalidFrame)
                }
            })
        }
    }
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void) { task.send(.string(text), completionHandler: completion) }
    func cancel() { task.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@available(iOS 13.0, macOS 10.15, *)
final class ConfiguredRealtimeClient: @unchecked Sendable {
    enum State: Equatable { case stopped, connecting, attaching, ready, refreshing, waitingToRetry, failed, closed }
    struct Callbacks {
        var onState: (State) -> Void = { _ in }
        var onReady: (_ firstForAttempt: Bool) -> Void = { _ in }
        var onMessage: (ConfiguredRealtimeMessage) -> Void = { _ in }
        var onDiagnostic: (_ fixedReasonCode: String) -> Void = { _ in }
    }
    struct Limits {
        var connectionTimeout: TimeInterval = 15
        var initialAttemptTimeout: TimeInterval = 15
        var refreshTimeout: TimeInterval = 60
        var acknowledgementTimeout: TimeInterval = 15
        var maximumPendingPublishes = 128
        var maximumEarlyMessages = 128
        var maximumEarlyBytes = 4_194_304
        var minimumRefreshInterval: TimeInterval = 30
    }
    typealias Refresh = (@escaping (Result<ConfiguredRealtimeTicket, Error>) -> Void) -> (() -> Void)?
    typealias SocketFactory = (URL) -> ConfiguredRealtimeSocket
    private(set) var state: State = .stopped
    private let callbacks: Callbacks
    private let refresh: Refresh
    private let limits: Limits
    private let makeSocket: SocketFactory
    private let jitter: () -> Double
    private var socket: ConfiguredRealtimeSocket?
    private var ticket: ConfiguredRealtimeTicket?
    private var attempt = UUID()
    private var generation = UUID()
    private var refreshID: UUID?
    private var cancelRefresh: (() -> Void)?
    private var terminal = true
    private var attached = false
    private var firstReadyDelivered = false
    private var reconnectAttempt = 0
    private var idleInterval: TimeInterval?
    private var lastReceived = ProcessInfo.processInfo.systemUptime
    private var lastRefreshStarted: Date?
    private var earlyMessages: [ConfiguredRealtimeMessage] = []
    private var earlyBytes = 0
    private var ledger = ConfiguredRealtimeACKLedger()
    private var publishCallbacks: [Int64: (Result<Void, Error>) -> Void] = [:]
    private var timers: [String: DispatchWorkItem] = [:]
    private var timerIDs: [String: UUID] = [:]

    init(callbacks: Callbacks, limits: Limits = Limits(), refresh: @escaping Refresh,
         socketFactory: SocketFactory? = nil, jitter: @escaping () -> Double = { Double.random(in: 0.8...1.2) }) {
        self.callbacks = callbacks; self.refresh = refresh; self.limits = limits; self.jitter = jitter
        makeSocket = socketFactory ?? { ConfiguredURLSessionSocket(url: $0) }
    }

    func connect(ticket: ConfiguredRealtimeTicket) {
        requireMain()
        stopInternal(reason: .connectionReplaced, state: .stopped)
        attempt = UUID(); terminal = false; firstReadyDelivered = false; reconnectAttempt = 0
        lastRefreshStarted = nil
        schedule("attempt", after: limits.initialAttemptTimeout) { [weak self] in
            guard let self = self, !self.firstReadyDelivered else { return }
            self.fail(.attemptTimeout)
        }
        beginConnection(ticket)
    }
    func stop() { requireMain(); stopInternal(reason: .stopped, state: .stopped) }

    func publish(name: String?, data: Any, completion: @escaping (Result<Void, Error>) -> Void) {
        requireMain()
        if ticket?.expiresAt.map({ $0 <= Date() }) == true {
            recover(.expiredConnection, immediately: true)
            deliverCompletion(completion, .failure(ConfiguredRealtimeError.expiredConnection)); return
        }
        guard !terminal, attached, let ticket = ticket else { deliverCompletion(completion, .failure(ConfiguredRealtimeError.notReady)); return }
        guard publishCallbacks.count < limits.maximumPendingPublishes else {
            deliverCompletion(completion, .failure(ConfiguredRealtimeError.capacityExceeded)); return
        }
        do {
            var message: [String: Any]
            if let string = data as? String { message = ["data": string] }
            else if data is [String: Any] || data is [Any] {
                guard JSONSerialization.isValidJSONObject(data),
                      let bytes = try? JSONSerialization.data(withJSONObject: data),
                      bytes.count <= ConfiguredRealtimeJSON.maximumBytes,
                      let string = String(data: bytes, encoding: .utf8) else {
                    throw ConfiguredRealtimeError.invalidMessage
                }
                message = ["data": string, "encoding": "json"]
            } else { throw ConfiguredRealtimeError.invalidMessage }
            if let name = name { message["name"] = name }
            _ = try ConfiguredRealtimeJSON.text(["messages": [message]])
            let serial = ledger.nextSerial
            let text = try ConfiguredRealtimeJSON.text(["action": 15, "channel": ticket.channel,
                                                        "msgSerial": NSNumber(value: serial), "messages": [message]])
            _ = try ledger.reserve()
            publishCallbacks[serial] = completion
            schedule("ack-\(serial)", after: limits.acknowledgementTimeout) { [weak self] in
                self?.completePublish(serial, .failure(ConfiguredRealtimeError.acknowledgementTimeout))
            }
            send(text) { [weak self] error in
                if error != nil { self?.completePublish(serial, .failure(ConfiguredRealtimeError.sendFailed)) }
            }
        } catch { deliverCompletion(completion, .failure(error)) }
    }

    func applicationDidBecomeActive() { requireMain(); resumeIfNeeded() }
    func networkBecameAvailable() { requireMain(); resumeIfNeeded() }
    func networkBecameUnavailable() {
        requireMain()
        guard !terminal, socket != nil else { return }
        recover(.disconnected, immediately: false)
    }

    private func beginConnection(_ newTicket: ConfiguredRealtimeTicket) {
        guard !terminal else { return }
        if let expiry = newTicket.expiresAt, expiry <= Date() { fail(.expiredConnection); return }
        invalidateSocket(reason: .connectionReplaced)
        ticket = newTicket
        generation = UUID(); let current = generation
        let newSocket = makeSocket(newTicket.url)
        socket = newSocket; attached = false; earlyMessages.removeAll(); earlyBytes = 0
        ledger = ConfiguredRealtimeACKLedger()
        transition(.connecting)
        guard generation == current, !terminal else { return }
        schedule("connection", after: limits.connectionTimeout) { [weak self] in
            self?.recover(.connectionTimeout, immediately: false)
        }
        newSocket.resume()
        receive(from: newSocket, generation: current)
        scheduleExpiry(newTicket)
    }
    private func receive(from source: ConfiguredRealtimeSocket, generation current: UUID) {
        source.receive { [weak self, weak source] result in
            DispatchQueue.main.async {
                guard let self = self, let source = source, !self.terminal,
                      self.generation == current, self.socket === source else { return }
                switch result {
                case .failure: self.recover(.disconnected, immediately: false)
                case .success(let bytes):
                    if self.ticket?.expiresAt.map({ $0 <= Date() }) == true {
                        self.recover(.expiredConnection, immediately: true); return
                    }
                    self.lastReceived = ProcessInfo.processInfo.systemUptime
                    self.resetWatchdog()
                    do { try self.handle(ConfiguredRealtimeFrame(json: bytes)) }
                    catch { self.fail(.invalidFrame) }
                    if self.generation == current, !self.terminal, self.socket === source {
                        self.receive(from: source, generation: current)
                    }
                }
            }
        }
    }
    private func handle(_ frame: ConfiguredRealtimeFrame) throws {
        switch frame.action {
        case 0, 23: break
        case 22:
            var pong: [String: Any] = ["action": 23]
            if let value = frame.object["id"], !(value is NSNull) {
                guard let id = value as? String else { throw ConfiguredRealtimeError.invalidFrame }
                pong["id"] = id
            }
            send(try ConfiguredRealtimeJSON.text(pong))
        case 4:
            guard let ticket = ticket, let idle = frame.idleTimeout else { throw ConfiguredRealtimeError.invalidFrame }
            if let details = frame.object["connectionDetails"] as? [String: Any],
               let client = details["clientId"], !(client is NSNull), (client as? String) != ticket.expectedClientID {
                throw ConfiguredRealtimeError.invalidIdentity
            }
            idleInterval = idle; resetWatchdog()
            guard state == .connecting else { diagnose("duplicateConnected"); return }
            transition(.attaching)
            send(ticket.attachJSON)
        case 11:
            guard frame.channel == ticket?.channel else { diagnose("foreignAttached"); return }
            guard state == .attaching else { diagnose("unexpectedAttached"); return }
            attached = true; reconnectAttempt = 0; cancelTimer("connection")
            let current = generation
            transition(.ready)
            guard !terminal, generation == current else { return }
            notify { [weak self] callbacks in
                guard let self = self else { return }
                let first = !self.firstReadyDelivered
                self.firstReadyDelivered = true; self.cancelTimer("attempt")
                callbacks.onReady(first)
            }
            let buffered = earlyMessages; earlyMessages.removeAll(); earlyBytes = 0
            for message in buffered {
                guard !terminal, generation == current else { break }
                notify { $0.onMessage(message) }
            }
        case 15:
            guard frame.channel == ticket?.channel else { diagnose("foreignMessage"); return }
            guard attached || state == .attaching else { diagnose("messageBeforeAttach"); return }
            guard let entries = frame.object["messages"] as? [Any] else { throw ConfiguredRealtimeError.invalidFrame }
            let current = generation
            let protocolID = try ConfiguredRealtimeJSON.optionalString(frame.object["id"])
            for (index, entry) in entries.enumerated() {
                guard !terminal, generation == current else { break }
                do {
                    let message = try ConfiguredRealtimeMessage.parse(entry, channel: frame.channel!, protocolID: protocolID, index: index)
                    if attached { notify { $0.onMessage(message) } }
                    else {
                        let size = try ConfiguredRealtimeJSON.text(["entry": entry]).utf8.count
                        guard earlyMessages.count < limits.maximumEarlyMessages,
                              size <= limits.maximumEarlyBytes - earlyBytes else {
                            fail(.capacityExceeded); return
                        }
                        earlyMessages.append(message); earlyBytes += size
                    }
                } catch { diagnose("messageRejected") }
            }
        case 1, 2:
            let result = try ledger.apply(frame)
            for serial in result.skipped { completePublish(serial, .failure(ConfiguredRealtimeError.acknowledgementSkipped)) }
            for serial in result.confirmed {
                completePublish(serial, frame.action == 1 ? .success(()) : .failure(ConfiguredRealtimeError.acknowledgementFailed))
            }
        case 6:
            recover(.disconnected, immediately: frame.credentialRejected)
        case 13:
            guard frame.channel == ticket?.channel else { diagnose("foreignDetached"); return }
            recover(.detached, immediately: false)
        case 8: stopInternal(reason: .serverClosed, state: .closed)
        case 9:
            if let channel = frame.channel, channel != ticket?.channel { diagnose("foreignError"); return }
            if frame.credentialRejected { recover(.expiredConnection, immediately: true) }
            else { fail(.serverRejected) }
        case 17: beginRefresh(preserveSocket: true)
        default: diagnose("unknownControlAction")
        }
    }

    private func send(_ text: String, completion: (@Sendable (Error?) -> Void)? = nil) {
        guard let source = socket else { completion?(ConfiguredRealtimeError.notReady); return }
        let current = generation
        source.send(text) { [weak self, weak source] error in
            DispatchQueue.main.async {
                guard let self = self, let source = source, self.generation == current,
                      !self.terminal, self.socket === source else { return }
                completion?(error == nil ? nil : ConfiguredRealtimeError.sendFailed)
                if error != nil { self.recover(.sendFailed, immediately: false) }
            }
        }
    }
    private func recover(_ reason: ConfiguredRealtimeError, immediately: Bool) {
        guard !terminal else { return }
        invalidateSocket(reason: reason)
        diagnose(reason.rawValue)
        if refreshID != nil { transition(.refreshing); return }
        cancelTimer("retry")
        if immediately { beginRefresh(preserveSocket: false); return }
        transition(.waitingToRetry)
        let exponent = min(reconnectAttempt, 5)
        let base = min(pow(2, Double(exponent)), 30)
        reconnectAttempt = min(reconnectAttempt + 1, 30)
        schedule("retry", after: base * min(max(jitter(), 0.8), 1.2)) { [weak self] in
            self?.beginRefresh(preserveSocket: false)
        }
    }
    private func beginRefresh(preserveSocket: Bool) {
        guard !terminal, refreshID == nil else { return }
        cancelTimer("retry"); cancelTimer("expiry")
        if !preserveSocket { invalidateSocket(reason: .connectionReplaced); transition(.refreshing) }
        if let started = lastRefreshStarted {
            let remaining = limits.minimumRefreshInterval - Date().timeIntervalSince(started)
            if remaining > 0 {
                if !preserveSocket { transition(.waitingToRetry) }
                schedule("retry", after: remaining) { [weak self] in
                    self?.beginRefresh(preserveSocket: preserveSocket)
                }
                return
            }
        }
        let operation = UUID(), currentAttempt = attempt
        refreshID = operation; lastRefreshStarted = Date()
        schedule("refresh", after: limits.refreshTimeout) { [weak self] in
            guard let self = self, self.refreshID == operation else { return }
            self.cancelCurrentRefresh(); self.recover(.refreshTimeout, immediately: false)
        }
        let cancellation = refresh { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, !self.terminal, self.attempt == currentAttempt,
                      self.refreshID == operation else { return }
                self.refreshID = nil; self.cancelRefresh = nil; self.cancelTimer("refresh")
                switch result {
                case .success(let fresh):
                    guard fresh.channel == self.ticket?.channel,
                          fresh.expectedClientID == self.ticket?.expectedClientID else {
                        self.fail(.invalidIdentity); return
                    }
                    self.beginConnection(fresh)
                case .failure: self.recover(.refreshFailed, immediately: false)
                }
            }
        }
        if !terminal, attempt == currentAttempt, refreshID == operation { cancelRefresh = cancellation }
        else if let cancellation = cancellation { DispatchQueue.main.async { cancellation() } }
    }
    private func scheduleExpiry(_ ticket: ConfiguredRealtimeTicket) {
        cancelTimer("expiry")
        guard let expiry = ticket.expiresAt else { return }
        let remaining = expiry.timeIntervalSinceNow
        schedule("credentialExpiry", after: max(0.001, remaining)) { [weak self] in
            self?.recover(.expiredConnection, immediately: true)
        }
        let desired = max(1, remaining - 60)
        let cooldown = lastRefreshStarted.map { max(0, limits.minimumRefreshInterval - Date().timeIntervalSince($0)) } ?? 0
        let delay = min(max(desired, cooldown), max(1, remaining))
        schedule("expiry", after: delay) { [weak self] in
            guard let self = self else { return }
            self.beginRefresh(preserveSocket: expiry > Date())
        }
    }
    private func resetWatchdog() {
        guard let interval = idleInterval, socket != nil else { return }
        schedule("watchdog", after: interval) { [weak self] in
            guard let self = self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastReceived >= interval {
                self.recover(.idleTimeout, immediately: false)
            } else { self.resetWatchdog() }
        }
    }
    private func resumeIfNeeded() {
        guard !terminal, refreshID == nil else { return }
        if let expiry = ticket?.expiresAt, expiry <= Date() { beginRefresh(preserveSocket: false); return }
        if let interval = idleInterval, socket != nil,
           ProcessInfo.processInfo.systemUptime - lastReceived >= interval {
            recover(.idleTimeout, immediately: true)
        } else if socket == nil { cancelTimer("retry"); beginRefresh(preserveSocket: false) }
    }
    private func completePublish(_ serial: Int64, _ result: Result<Void, Error>) {
        _ = ledger.remove(serial); cancelTimer("ack-\(serial)")
        let callback = publishCallbacks.removeValue(forKey: serial)
        if let callback = callback { deliverCompletion(callback, result) }
    }
    private func invalidateSocket(reason: ConfiguredRealtimeError) {
        generation = UUID(); socket?.cancel(); socket = nil; attached = false; idleInterval = nil
        earlyMessages.removeAll(); earlyBytes = 0
        for key in ["connection", "watchdog", "expiry", "credentialExpiry"] { cancelTimer(key) }
        let callbacks = publishCallbacks
        publishCallbacks.removeAll(); _ = ledger.drain()
        for serial in callbacks.keys { cancelTimer("ack-\(serial)") }
        for callback in callbacks.values { deliverCompletion(callback, .failure(reason)) }
    }
    private func cancelCurrentRefresh() {
        refreshID = nil; cancelTimer("refresh")
        let cancel = cancelRefresh; cancelRefresh = nil
        if let cancel = cancel { DispatchQueue.main.async { cancel() } }
    }
    private func stopInternal(reason: ConfiguredRealtimeError, state: State) {
        terminal = true; attempt = UUID()
        let pendingTimers = timers.values; timers.removeAll(); timerIDs.removeAll()
        for work in pendingTimers { work.cancel() }
        cancelCurrentRefresh(); invalidateSocket(reason: reason); ticket = nil
        transition(state)
    }
    private func fail(_ reason: ConfiguredRealtimeError) { stopInternal(reason: reason, state: .failed); diagnose(reason.rawValue) }
    private func diagnose(_ code: String) { notify { $0.onDiagnostic(code) } }
    private func transition(_ next: State) { state = next; notify { $0.onState(next) } }
    private func notify(_ action: @escaping (Callbacks) -> Void) {
        let currentAttempt = attempt, currentGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.attempt == currentAttempt, self.generation == currentGeneration else { return }
            action(self.callbacks)
        }
    }
    private func deliverCompletion(_ callback: @escaping (Result<Void, Error>) -> Void, _ result: Result<Void, Error>) {
        DispatchQueue.main.async { callback(result) }
    }
    private func schedule(_ key: String, after seconds: TimeInterval, _ block: @escaping () -> Void) {
        cancelTimer(key)
        let currentAttempt = attempt, timerID = UUID()
        timerIDs[key] = timerID
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.terminal, self.attempt == currentAttempt,
                  self.timerIDs[key] == timerID else { return }
            self.timers.removeValue(forKey: key); self.timerIDs.removeValue(forKey: key)
            block()
        }
        timers[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, seconds), execute: item)
    }
    private func cancelTimer(_ key: String) { timers.removeValue(forKey: key)?.cancel(); timerIDs.removeValue(forKey: key) }
    private func requireMain() { precondition(Thread.isMainThread, "ConfiguredRealtimeClient must be owned on the main thread") }
    deinit {
        socket?.cancel()
        let cancellation = cancelRefresh
        if let cancellation = cancellation { DispatchQueue.main.async { cancellation() } }
        for timer in timers.values { timer.cancel() }
        let callbacks = Array(publishCallbacks.values)
        DispatchQueue.main.async { for callback in callbacks { callback(.failure(ConfiguredRealtimeError.stopped)) } }
    }
}

@MainActor
final class ConfiguredRealtimeTransport {
    enum State { case connecting, connected, subscribed, reconnecting, failed, closed, stopped }
    typealias Refresh = @MainActor () async throws -> ConfiguredRealtimeTicket
    var onMessage: (@MainActor (ConfiguredRealtimeMessage) -> Void)?
    var onState: (@MainActor (State) -> Void)?
    private var client: ConfiguredRealtimeClient?
    private var generation = UUID()
    private var pathMonitor: NWPathMonitor?
    private var activeObserver: NSObjectProtocol?
    private var wasOnline: Bool?
    private let log = Logger(subsystem: "com.nanalantern.harbortide", category: "Realtime")

    func start(configuration: ConfiguredRealtimeTicket, refresh: @escaping Refresh) {
        stop()
        let current = generation
        let callbacks = ConfiguredRealtimeClient.Callbacks(
            onState: { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    switch state {
                    case .connecting: self.onState?(.connecting)
                    case .attaching: self.onState?(.connected)
                    case .refreshing, .waitingToRetry: self.onState?(.reconnecting)
                    case .failed: self.onState?(.failed)
                    case .closed: self.onState?(.closed)
                    case .stopped: self.onState?(.stopped)
                    case .ready: break
                    }
                }
            },
            onReady: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.onState?(.subscribed)
                }
            },
            onMessage: { [weak self] message in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.onMessage?(message)
                }
            },
            onDiagnostic: { [weak self] code in
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.log.notice("Transport reason=\(code, privacy: .public)")
                }
            })
        let connection = ConfiguredRealtimeClient(callbacks: callbacks, refresh: { completion in
            MainActor.assumeIsolated {
                let task = Task { @MainActor in
                    do {
                        let ticket = try await refresh()
                        try Task.checkCancellation()
                        completion(.success(ticket))
                    } catch { completion(.failure(error)) }
                }
                return { task.cancel() }
            }
        })
        client = connection
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.client?.applicationDidBecomeActive()
            }
        }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                defer { self.wasOnline = online }
                guard self.wasOnline != online else { return }
                if online { self.client?.networkBecameAvailable() }
                else { self.client?.networkBecameUnavailable() }
            }
        }
        connection.connect(ticket: configuration)
        monitor.start(queue: DispatchQueue(label: "com.nanalantern.realtime-path"))
    }

    func stop() {
        generation = UUID()
        pathMonitor?.cancel()
        pathMonitor = nil
        wasOnline = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        client?.stop()
        client = nil
    }

    deinit {
        pathMonitor?.cancel()
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }
}
