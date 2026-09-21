import Foundation

enum NanaAServiceConfiguration {
    static let interfaceBaseURL = URL(string: "https://lantern.party.top")!
    static let pathPrefix = "harbortide/v1"
    static let versionFieldName = "nanaReleaseVersion"
    static let clientName = "Nana"

    static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

struct NanaAPIEnvelope<Value: Decodable>: Decodable {
    let schemaVersion: String
    let requestID: String
    let data: Value
    let meta: NanaAPIMetadata?
}

struct NanaAPIMetadata: Decodable {
    let source: String?
    let contentRevision: String?
    let schemaVersion: String?
}

struct NanaHomeFeedPayload: Decodable {
    let rooms: [NanaLiveRoom]
    let posts: [NanaPost]
}

struct NanaRoomDetailPayload: Decodable {
    let room: NanaLiveRoom
    let seats: [NanaRoomSeat]
    let messages: [NanaRoomChatMessage]
    let gifts: [NanaGift]
}

struct NanaProfilePayload: Decodable {
    let profile: NanaProfile
}

struct NanaPostPayload: Decodable {
    let post: NanaPost
}

struct NanaSearchPayload: Decodable {
    let profiles: [NanaProfile]
    let rooms: [NanaLiveRoom]
    let posts: [NanaPost]
}

struct NanaConversationsPayload: Decodable {
    let conversations: [NanaConversation]
}

struct NanaMessagesPayload: Decodable {
    let messages: [NanaMessage]
}

struct NanaWalletPayload: Decodable {
    let wallet: NanaWalletSnapshot
}

struct NanaGiftsPayload: Decodable {
    let gifts: [NanaGift]
}

struct NanaAssetDescriptor: Codable, Hashable {
    let assetKey: String
    let kind: String
    let bundlePath: String
}

struct NanaAssetManifestPayload: Decodable {
    let assets: [NanaAssetDescriptor]
}

/// Only routes present in the published export are allowed. Detail IDs are literal,
/// because the current platform export does not define parameterized routes.
enum NanaReadEndpoint: String, Codable, CaseIterable {
    case bootstrap = "bootstrap"
    case homeFeed = "home/feed"
    case rooms = "rooms"
    case auroraRoom = "rooms/room-aurora"
    case avaProfile = "profiles/profile-ava"
    case echoesPost = "posts/post-echoes"
    case search = "search"
    case conversations = "conversations"
    case avaMessages = "conversations/conversation-ava/messages"
    case wallet = "wallet"
    case gifts = "gifts"
    case assetManifest = "assets/manifest"
}

struct NanaReadRequest {
    let endpoint: NanaReadEndpoint

    func url(relativeTo origin: URL) throws -> URL {
        guard origin.scheme == "https", origin.host != nil else { throw NanaAServiceError.invalidResponse }
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        components?.path = "/\(NanaAServiceConfiguration.pathPrefix)/\(endpoint.rawValue)"
        components?.queryItems = [URLQueryItem(name: NanaAServiceConfiguration.versionFieldName,
                                             value: NanaAServiceConfiguration.clientVersion)]
        guard let url = components?.url else { throw NanaAServiceError.invalidResponse }
        return url
    }
}

/// Local, sanitized errors; the export does not define a server error JSON schema.
/// Never display or log raw bodies, tokens, signature values or transport URLs.
enum NanaAServiceError: Error, LocalizedError, Equatable {
    case invalidResponse, incompatibleSchema, timeout, offline, transport
    case unauthorizedContent, forbidden, notFound, authenticationUnavailable, writeUnavailable, secureStorage
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "We couldn't read this content. Please try again."
        case .incompatibleSchema: return "This content needs a compatible app update."
        case .timeout: return "The request took too long. Please try again."
        case .offline: return "You're offline. Saved content is available when present."
        case .transport: return "Nana couldn't reach the service. Please try again later."
        case .unauthorizedContent: return "The content service didn't authorize this request. Your local sign-in is still saved."
        case .forbidden: return "The content service has restricted this request. Please try again later."
        case .notFound: return "This content is no longer available."
        case .authenticationUnavailable: return "Account sign-in is not available yet. Please try again when the account service is ready."
        case .writeUnavailable: return "This action is not available yet. Nothing was sent or changed."
        case .secureStorage: return "Your session couldn't be saved securely. Please try again."
        case .httpStatus: return "The service is temporarily unavailable. Please try again."
        }
    }

    var canRetry: Bool {
        switch self {
        case .timeout, .offline, .transport: return true
        case .httpStatus(let code): return code == 408 || code == 429 || (500...599).contains(code)
        default: return false
        }
    }
}

struct NanaAServiceClient {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = NanaAServiceConfiguration.interfaceBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.makeSession()
    }

    func read<Value: Decodable>(_ endpoint: NanaReadEndpoint, as: Value.Type) async throws -> Value {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                return try await perform(NanaReadRequest(endpoint: endpoint), as: Value.self)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let failure = Self.sanitize(error)
                guard failure.canRetry, attempt < 2 else { throw failure }
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 500 : 1000))
            }
        }
        throw NanaAServiceError.transport
    }

    private func perform<Value: Decodable>(_ read: NanaReadRequest, as: Value.Type) async throws -> Value {
        var request = URLRequest(url: try read.url(relativeTo: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // No Authorization header: none is specified by the published read-only contract.
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NanaAServiceError.invalidResponse }
        switch response.statusCode {
        case 200..<300: break
        case 401: throw NanaAServiceError.unauthorizedContent
        case 403: throw NanaAServiceError.forbidden
        case 404: throw NanaAServiceError.notFound
        default: throw NanaAServiceError.httpStatus(response.statusCode)
        }
        guard data.count <= 8 * 1024 * 1024 else { throw NanaAServiceError.invalidResponse }
        guard let envelope = try? JSONDecoder().decode(NanaAPIEnvelope<Value>.self, from: data) else {
            throw NanaAServiceError.invalidResponse
        }
        guard envelope.schemaVersion == "1.0" else { throw NanaAServiceError.incompatibleSchema }
        return envelope.data
    }

    static func sanitize(_ error: Error) -> NanaAServiceError {
        if let error = error as? NanaAServiceError { return error }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost: return .offline
            default: return .transport
            }
        }
        return .invalidResponse
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: NanaReadRedirectPolicy(), delegateQueue: nil)
    }
}

private final class NanaReadRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              target.scheme == "https", target.host == original.host,
              target.port == original.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}

struct NanaRoomsPayload: Decodable {
    let rooms: [NanaLiveRoom]
}
