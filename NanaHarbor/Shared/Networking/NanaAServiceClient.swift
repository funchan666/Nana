import Foundation

struct NanaAServiceConfiguration {
    static let interfaceBaseURL = URL(string: IntegrationContract.baseURLString ?? "https://lantern.nanacc.top")!
    static let webBaseURL = URL(string: "https://nanacc.top")!
    static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

struct NanaAPIEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: Value
}

struct NanaAPINoDataEnvelope: Decodable {
    let code: Int
    let message: String
}

struct NanaHomeFeedPayload: Decodable { let rooms: [NanaLiveRoom]; let posts: [NanaPost] }
struct NanaRoomDetailPayload: Decodable { let room: NanaLiveRoom; let seats: [NanaRoomSeat]; let messages: [NanaRoomChatMessage]; let gifts: [NanaGift] }
struct NanaProfilePayload: Decodable { let profile: NanaProfile }
struct NanaPostPayload: Decodable { let post: NanaPost }
struct NanaSearchPayload: Decodable { let profiles: [NanaProfile]; let rooms: [NanaLiveRoom]; let posts: [NanaPost] }
struct NanaConversationsPayload: Decodable { let conversations: [NanaConversation] }
struct NanaMessagesPayload: Decodable { let messages: [NanaMessage] }
struct NanaWalletPayload: Decodable { let wallet: NanaWalletSnapshot }
struct NanaGiftsPayload: Decodable { let gifts: [NanaGift] }
struct NanaAssetDescriptor: Codable, Hashable { let assetKey: String; let kind: String; let bundlePath: String }
struct NanaAssetManifestPayload: Decodable { let assets: [NanaAssetDescriptor] }

enum NanaReadEndpoint: String, Codable, CaseIterable {
    case bootstrap, homeFeed, rooms, auroraRoom, avaProfile, echoesPost, search, conversations, avaMessages, wallet, gifts, assetManifest

    var path: String {
        switch self {
        case .bootstrap: return ConfiguredContentPaths.bootstrap
        case .homeFeed: return ConfiguredContentPaths.homeFeed
        case .rooms: return ConfiguredContentPaths.rooms
        case .auroraRoom: return ConfiguredContentPaths.auroraRoom
        case .avaProfile: return ConfiguredContentPaths.avaProfile
        case .echoesPost: return ConfiguredContentPaths.echoesPost
        case .search: return ConfiguredContentPaths.search
        case .conversations: return ConfiguredContentPaths.conversations
        case .avaMessages: return ConfiguredContentPaths.avaMessages
        case .wallet: return ConfiguredContentPaths.wallet
        case .gifts: return ConfiguredContentPaths.gifts
        case .assetManifest: return ConfiguredContentPaths.assetManifest
        }
    }
}

struct NanaReadRequest {
    let endpoint: NanaReadEndpoint
    func url(relativeTo origin: URL) throws -> URL {
        guard origin.scheme == "https", origin.host != nil else { throw NanaAServiceError.invalidResponse }
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        components?.path = endpoint.path
        guard let url = components?.url else { throw NanaAServiceError.invalidResponse }
        return url
    }
}

enum NanaAServiceError: Error, LocalizedError, Equatable {
    case invalidResponse, incompatibleSchema, timeout, offline, transport, secureConnection
    case unauthorizedContent, forbidden, notFound, authenticationUnavailable, writeUnavailable, secureStorage
    case httpStatus(Int), authenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "We couldn't read this content. Please try again."
        case .incompatibleSchema: return "This content needs a compatible app update."
        case .timeout: return "The request took too long. Please try again."
        case .offline: return "You're offline. Saved content is available when present."
        case .transport: return "Nana couldn't reach the service. Please try again later."
        case .secureConnection: return "The service connection isn't ready yet. Please try again later."
        case .unauthorizedContent: return "We couldn't refresh this content. Please try again later."
        case .forbidden: return "The content service has restricted this request. Please try again later."
        case .notFound: return "This content is no longer available."
        case .authenticationUnavailable: return "Account sign-in is not available yet. Please try again when the account service is ready."
        case .writeUnavailable: return "This action is not available yet. Nothing was sent or changed."
        case .secureStorage: return "Your session couldn't be saved securely. Please try again."
        case .httpStatus: return "The service is temporarily unavailable. Please try again."
        case .authenticationFailed(let message): return message
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
            do { return try await perform(NanaReadRequest(endpoint: endpoint), as: Value.self) }
            catch is CancellationError { throw CancellationError() }
            catch {
                let failure = Self.sanitize(error)
                guard failure.canRetry, attempt < 2 else { throw failure }
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 500 : 1000))
            }
        }
        throw NanaAServiceError.transport
    }

    func probeOrigin() async throws {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) else { throw NanaAServiceError.transport }
    }

    func request(path: String, method: String, body: [String: Any]? = nil) async throws -> (HTTPURLResponse, [String: Any]) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "https", url.host == baseURL.host else { throw NanaAServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NanaAServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode { case 401: throw NanaAServiceError.unauthorizedContent; case 403: throw NanaAServiceError.forbidden; case 404: throw NanaAServiceError.notFound; default: throw NanaAServiceError.httpStatus(http.statusCode) }
        }
        guard data.count <= 8 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NanaAServiceError.invalidResponse }
        return (http, object)
    }

    private func perform<Value: Decodable>(_ read: NanaReadRequest, as: Value.Type) async throws -> Value {
        var request = URLRequest(url: try read.url(relativeTo: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NanaAServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            switch response.statusCode { case 401: throw NanaAServiceError.unauthorizedContent; case 403: throw NanaAServiceError.forbidden; case 404: throw NanaAServiceError.notFound; default: throw NanaAServiceError.httpStatus(response.statusCode) }
        }
        guard data.count <= 8 * 1024 * 1024 else { throw NanaAServiceError.invalidResponse }
        let envelope = try JSONDecoder().decode(NanaAPIEnvelope<Value>.self, from: data)
        guard envelope.code == 0 else { throw NanaAServiceError.authenticationFailed(envelope.message) }
        return envelope.data
    }

    static func sanitize(_ error: Error) -> NanaAServiceError {
        if let error = error as? NanaAServiceError { return error }
        if let error = error as? URLError {
            switch error.code { case .timedOut: return .timeout; case .notConnectedToInternet, .networkConnectionLost: return .offline; case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected: return .secureConnection; default: return .transport }
        }
        return .invalidResponse
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: NanaReadRedirectPolicy(), delegateQueue: nil)
    }
}

private final class NanaReadRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url, target.scheme == "https", target.host == original.host, target.port == original.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}

struct NanaRoomsPayload: Decodable { let rooms: [NanaLiveRoom] }
