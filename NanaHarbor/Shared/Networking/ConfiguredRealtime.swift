import Foundation
import CoreFoundation

struct ConfiguredRealtimeConfiguration {
    enum Failure: Error { case invalidToken, ambiguousChannel, invalidPermissions, invalidClient }
    let tokenRequest: [String: Any]
    let channelName: String
    let clientID: String
    let canReadHistory: Bool

    init(tokenRequest request: [String: Any], expectedClientID: String) throws {
        for key in ["keyName", "nonce", "mac"] {
            guard let text = request[key] as? String, !text.isEmpty else { throw Failure.invalidToken }
        }
        for key in ["timestamp", "ttl"] {
            guard let number = request[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  number.doubleValue > 0 else { throw Failure.invalidToken }
        }
        guard !expectedClientID.isEmpty, expectedClientID != "*",
              let clientID = request["clientId"] as? String, clientID == expectedClientID else {
            throw Failure.invalidClient
        }
        guard let capability = request["capability"] as? String,
              let bytes = capability.data(using: .utf8),
              let channels = try JSONSerialization.jsonObject(with: bytes) as? [String: [String]],
              channels.count == 1, let channel = channels.first,
              !channel.key.isEmpty, !channel.key.contains("*") else { throw Failure.ambiguousChannel }
        let permissions = Set(channel.value)
        guard permissions.contains("subscribe"), permissions.contains("publish") else {
            throw Failure.invalidPermissions
        }
        tokenRequest = request
        channelName = channel.key
        self.clientID = clientID
        canReadHistory = permissions.contains("history")
    }
}

import UIKit
import Ably

final class ConfiguredRealtimeTransport {
    enum State { case connecting, connected, subscribed, reconnecting, failed, stopped }
    typealias Refresh = (@escaping (Result<ConfiguredRealtimeConfiguration, Error>) -> Void) -> Void
    var onMessage: ((ARTMessage) -> Void)?
    var onState: ((State) -> Void)?

    private var realtime: ARTRealtime?
    private var channel: ARTRealtimeChannel?
    private var configuration: ConfiguredRealtimeConfiguration?
    private var firstToken: [String: Any]?
    private var refresh: Refresh?
    private var generation = UUID()
    private var pendingAuthentication: ARTTokenDetailsCompatibleCallback?
    private var isPinging = false
    private var activeObserver: NSObjectProtocol?

    init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resume() }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        channel?.unsubscribe()
        channel?.off()
        realtime?.connection.off()
        realtime?.close()
    }

    func start(configuration: ConfiguredRealtimeConfiguration, refresh: @escaping Refresh) {
        stop()
        let id = generation
        self.configuration = configuration
        firstToken = configuration.tokenRequest
        self.refresh = refresh
        let options = ARTClientOptions()
        options.autoConnect = false
        options.clientId = configuration.clientID
        options.dispatchQueue = .main
        options.logLevel = .none
        options.disconnectedRetryTimeout = 3
        options.suspendedRetryTimeout = 5
        options.channelRetryTimeout = 3
        options.authCallback = { [weak self] _, callback in
            Self.debugLog("authCallback", "requested")
            guard let self, self.generation == id else {
                callback(nil, Self.cancelledError); return
            }
            self.provideToken(callback, generation: id)
        }
        let client = ARTRealtime(options: options)
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.params = ["rewind": "1"]
        Self.debugLog("subscribe", ["channel": configuration.channelName, "rewind": "1"])
        let channel = client.channels.get(configuration.channelName, options: channelOptions)
        realtime = client
        self.channel = channel
        channel.subscribe { [weak self] message in
            Self.debugReceivedMessage(message, channelName: configuration.channelName)
            guard let self, self.generation == id else {
                Self.debugLog("message ignored", "stale connection")
                return
            }
            self.onMessage?(message)
        }
        channel.on { [weak self] change in
            Self.debugLog("channel state", "\(change.previous) -> \(change.current); reason=\(String(describing: change.reason))")
            guard let self, self.generation == id else { return }
            if change.current == .attached { self.onState?(.subscribed) }
            else if change.current == .failed { self.onState?(.failed) }
        }
        client.connection.on { [weak self] change in
            Self.debugLog("connection state", "\(change.previous) -> \(change.current); reason=\(String(describing: change.reason))")
            guard let self, self.generation == id else { return }
            switch change.current {
            case .connected:
                self.onState?(.connected)
                if self.channel?.state == .attached { self.onState?(.subscribed) }
            case .failed: self.onState?(.failed)
            case .disconnected, .suspended: self.onState?(.reconnecting)
            default: break
            }
        }
        onState?(.connecting)
        client.connect()
    }

    func stop() {
        generation = UUID()
        let pending = pendingAuthentication
        pendingAuthentication = nil
        pending?(nil, Self.cancelledError)
        isPinging = false
        channel?.unsubscribe()
        channel?.off()
        realtime?.connection.off()
        realtime?.close()
        channel = nil
        realtime = nil
        configuration = nil
        firstToken = nil
        refresh = nil
        onState?(.stopped)
    }

    func publishResult(_ payload: [String: Any], completion: @escaping (Bool) -> Void) {
        publish(name: "native:result", payload: payload, completion: completion)
    }

    func publish(name: String, payload: Any, completion: @escaping (Bool) -> Void) {
        guard let channel, channel.state == .attached, realtime?.connection.state == .connected else {
            completion(false); return
        }
        let id = generation
        Self.debugLog("publish \(name) payload", payload)
        channel.publish(name, data: payload) { [weak self] error in
            Self.debugLog("publish callback", error.map { String(describing: $0) } ?? "success")
            guard let self, self.generation == id else { completion(false); return }
            completion(error == nil)
        }
    }

    private func provideToken(_ callback: @escaping ARTTokenDetailsCompatibleCallback, generation id: UUID) {
        if let firstToken {
            self.firstToken = nil
            Self.complete(firstToken, callback: callback)
            return
        }
        guard let refresh else { callback(nil, Self.cancelledError); return }
        guard pendingAuthentication == nil else {
            callback(nil, NSError(domain: "ConfiguredRealtime", code: 409)); return
        }
        pendingAuthentication = callback
        Self.debugLog("auth renewal", "requesting auth_status")
        refresh { [weak self] result in
            switch result {
            case .success: Self.debugLog("auth renewal callback", "success")
            case .failure(let error): Self.debugLog("auth renewal callback", String(describing: error))
            }
            guard let self, self.generation == id, let current = self.configuration,
                  let callback = self.pendingAuthentication else { return }
            self.pendingAuthentication = nil
            switch result {
            case .success(let renewed):
                guard renewed.channelName == current.channelName, renewed.clientID == current.clientID,
                      renewed.tokenRequest["nonce"] as? String != current.tokenRequest["nonce"] as? String else {
                    callback(nil, NSError(domain: "ConfiguredRealtime", code: 409)); return
                }
                self.configuration = renewed
                Self.complete(renewed.tokenRequest, callback: callback)
            case .failure:
                callback(nil, NSError(domain: "ConfiguredRealtime", code: 503))
            }
        }
    }

    private static func complete(_ request: [String: Any], callback: @escaping ARTTokenDetailsCompatibleCallback) {
        do {
            let token = try ARTTokenRequest.fromJson(request as NSDictionary)
            Self.debugLog("auth callback completion", "TokenRequest parsed successfully")
            callback(token, nil)
        } catch {
            Self.debugLog("auth callback completion", String(describing: error))
            callback(nil, NSError(domain: "ConfiguredRealtime", code: 422))
        }
    }

    private static func debugReceivedMessage(_ message: ARTMessage, channelName: String) {
        #if DEBUG
        debugLog("received message JSON", [
            "channel": channelName,
            "name": message.name as Any? ?? NSNull(),
            "id": message.id as Any? ?? NSNull(),
            "clientId": message.clientId as Any? ?? NSNull(),
            "connectionId": message.connectionId as Any? ?? NSNull(),
            "data": message.data ?? NSNull(),
            "encoding": message.encoding as Any? ?? NSNull(),
            "timestamp": message.timestamp.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(),
            "extras": message.extras as Any? ?? NSNull()
        ])
        let raw = message.data ?? NSNull()
        let jsonBytes: Data?
        if let text = raw as? String { jsonBytes = text.data(using: .utf8) }
        else { jsonBytes = raw as? Data }
        if let jsonBytes, let json = try? JSONSerialization.jsonObject(with: jsonBytes, options: [.fragmentsAllowed]) {
            debugLog("message data JSON", json)
        } else {
            debugLog("message data JSON", raw)
        }
        #endif
    }

    private static func debugLog(_ event: String, _ value: @autoclosure () -> Any) {
        #if DEBUG
        func jsonValue(_ value: Any) -> Any {
            if let bytes = value as? Data { return ["base64": bytes.base64EncodedString()] }
            if let object = value as? [String: Any] { return object.mapValues { jsonValue($0) } }
            if let items = value as? [Any] { return items.map { jsonValue($0) } }
            if value is String || value is NSNumber || value is NSNull { return value }
            return String(describing: value)
        }
        let payload = jsonValue(value())
        let formatted = (try? JSONSerialization.data(withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: payload)
        print("[Realtime] \(event):\n\(formatted)")
        #endif
    }

    private static var cancelledError: NSError { NSError(domain: "ConfiguredRealtime", code: NSUserCancelledError) }

    private func resume() {
        guard let realtime else { return }
        let id = generation
        if realtime.connection.state == .connected {
            guard !isPinging else { return }
            isPinging = true
            realtime.ping { [weak self, weak realtime] error in
                Self.debugLog("ping callback", error.map { String(describing: $0) } ?? "success")
                guard let self, self.generation == id, let realtime else { return }
                self.isPinging = false
                guard error != nil else { return }
                realtime.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak realtime] in
                    guard let self, self.generation == id else { return }
                    realtime?.connect()
                }
            }
        } else if realtime.connection.state != .connecting {
            realtime.connect()
        }
    }
}
