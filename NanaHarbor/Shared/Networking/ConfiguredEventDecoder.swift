import Foundation

struct ConfiguredCoreEvent {
    enum Kind: CaseIterable { case page, purchase, expire, externalOpen }
    enum Failure: Error { case sender, invalidData, messageID, unknownEvent, ambiguousEvent }
    let requestID: UUID
    let messageID: String
    let kind: Kind
    let fields: [String: Any]

    static func normalizedObject(_ raw: Any?) -> [String: Any]? {
        if let object = raw as? [String: Any] { return object }
        let bytes: Data?
        if let text = raw as? String { bytes = text.data(using: .utf8) }
        else { bytes = raw as? Data }
        guard let bytes else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }

    static func value(in fields: [String: Any], path: [String]) -> Any? {
        guard !path.isEmpty else { return nil }
        var current: Any = fields
        for component in path {
            guard let object = current as? [String: Any], let next = object[component] else { return nil }
            current = next
        }
        return current
    }

    private static func binding(_ kind: Kind) -> (name: String, path: [String]) {
        switch kind {
        case .page: return (IntegrationContract.pageSignal, IntegrationContract.pageDiscriminator)
        case .purchase: return (IntegrationContract.purchaseSignal, IntegrationContract.purchaseDiscriminator)
        case .expire: return (IntegrationContract.expirySignal, IntegrationContract.expiryDiscriminator)
        case .externalOpen: return (IntegrationContract.externalSignal, IntegrationContract.externalDiscriminator)
        }
    }

    private static func discriminatedKinds(_ object: [String: Any]) -> [Kind] {
        Kind.allCases.filter { kind in
            let rule = binding(kind)
            return value(in: object, path: rule.path) as? String == rule.name
        }
    }

    private static func eventEnvelope(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= 16_384 else { return nil }
        if let object = normalizedObject(text) { return object }
        for encoded in [text, "\"" + text + "\""] {
            guard let bytes = encoded.data(using: .utf8),
                  let decoded = (try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])) as? String,
                  let object = normalizedObject(decoded) else { continue }
            return object
        }
        return nil
    }

    private static func identifiedKind(_ text: String) throws -> Kind {
        if let envelope = eventEnvelope(text) {
            let matches = discriminatedKinds(envelope)
            guard !matches.isEmpty else { throw Failure.unknownEvent }
            guard matches.count == 1 else { throw Failure.ambiguousEvent }
            guard IntegrationContract.acceptsSerializedExpiry, matches[0] == .expire else { throw Failure.unknownEvent }
            return matches[0]
        }
        guard let kind = Kind.allCases.first(where: { binding($0).name == text }) else { throw Failure.unknownEvent }
        return kind
    }

    static func parse(requestID: UUID, transportID: String?, name: String?, clientID: String?, data: Any?) throws -> Self {
        let sender = clientID ?? ""
        guard sender != IntegrationContract.ablyClientID,
              sender.isEmpty ? IntegrationContract.allowsMissingSender : IntegrationContract.serverClientIDs.contains(sender) else {
            throw Failure.sender
        }
        guard let fields = normalizedObject(data) else { throw Failure.invalidData }
        let messageID = (fields["msgId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? transportID
        guard let messageID, !messageID.isEmpty else { throw Failure.messageID }

        var candidates = discriminatedKinds(fields)
        if let name, !name.isEmpty { candidates.append(try identifiedKind(name)) }
        if let capability = fields["capability"] {
            guard let text = capability as? String, !text.isEmpty else { throw Failure.invalidData }
            candidates.append(try identifiedKind(text))
        }
        guard let kind = candidates.first else { throw Failure.unknownEvent }
        guard candidates.allSatisfy({ $0 == kind }) else { throw Failure.ambiguousEvent }
        return Self(requestID: requestID, messageID: messageID, kind: kind, fields: fields)
    }

    private func string(at path: [String]) -> String? {
        guard let text = Self.value(in: fields, path: path) as? String, !text.contains("#{") else { return nil }
        return text
    }

    enum PageDestination {
        case notPage
        case absent
        case url(URL)
        case invalid
    }

    var pageDestination: PageDestination {
        guard kind == .page else { return .notPage }
        let path = IntegrationContract.pageAddressPath
        guard !path.isEmpty else { return .invalid }
        var current: Any = fields
        for component in path {
            guard let object = current as? [String: Any] else { return .invalid }
            guard let next = object[component], !(next is NSNull) else { return .absent }
            current = next
        }
        guard let raw = current as? String else { return .invalid }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .absent }
        guard let url = Self.webURL(raw) else { return .invalid }
        return .url(url)
    }

    var pageURL: URL? {
        if case let .url(url) = pageDestination { return url }
        return nil
    }

    var purchase: (sku: String, reference: String)? {
        guard kind == .purchase, let product = string(at: IntegrationContract.purchaseItemPath),
              let reference = string(at: IntegrationContract.purchaseReferencePath),
              !product.isEmpty, !product.contains(where: { $0.isWhitespace }),
              !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (product, reference)
    }

    var externalURL: URL? {
        guard kind == .externalOpen, let raw = string(at: IntegrationContract.externalAddressPath) else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }),
              let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    static func webURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("#{"), !text.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}
