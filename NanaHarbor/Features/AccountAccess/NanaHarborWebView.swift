import AVFoundation
import Combine
import SwiftUI
import WebKit

@MainActor
struct NanaHarborWebView: UIViewRepresentable {
    @ObservedObject var document: NanaWebDocument

    func makeUIView(context: Context) -> WKWebView { document.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

@MainActor
final class NanaWebDocument: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isAttached = false
    let webView: NanaWebSurface
    private var address: URL?
    private var generation = UUID()
    private var navigation: WKNavigation?
    private var acceptedResponse = false
    private var deadline: Task<Void, Never>?
    private var permissionReplies: [UUID: (WKPermissionDecision) -> Void] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = NanaWebSurface(frame: .zero, configuration: configuration)
        super.init()
        webView.onAttachmentChange = { [weak self] attached in
            Task { @MainActor [weak self] in
                guard let self, self.isAttached != attached else { return }
                self.isAttached = attached
            }
        }
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.10, green: 0.02, blue: 0.20, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    func prepare(_ address: URL) {
        stop()
        self.address = address
        phase = .loading
        navigation = webView.load(URLRequest(url: address, timeoutInterval: 30))
        armDeadline()
    }

    func retry() {
        guard let address else { return }
        prepare(address)
    }

    func stop() {
        generation = UUID()
        deadline?.cancel()
        deadline = nil
        navigation = nil
        acceptedResponse = false
        address = nil
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        cancelPermissions()
        phase = .idle
    }

    private func armDeadline() {
        deadline?.cancel()
        let revision = generation
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.generation == revision else { return }
            self.fail("The page took too long to respond. Please retry.")
        }
    }

    private func cancelPermissions() {
        let replies = Array(permissionReplies.values)
        permissionReplies.removeAll()
        replies.forEach { $0(.deny) }
    }

    private func fail(_ message: String) {
        generation = UUID()
        cancelPermissions()
        deadline?.cancel()
        deadline = nil
        navigation = nil
        acceptedResponse = false
        webView.stopLoading()
        phase = .failed(message)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard address != nil else { return }
        self.navigation = navigation
        generation = UUID()
        cancelPermissions()
        acceptedResponse = false
        armDeadline()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard address != nil else { decisionHandler(.cancel); return }
        guard navigationResponse.isForMainFrame else { decisionHandler(.allow); return }
        guard let response = navigationResponse.response as? HTTPURLResponse,
              (200..<400).contains(response.statusCode), navigationResponse.canShowMIMEType,
              ["text/html", "application/xhtml+xml"].contains(response.mimeType?.lowercased() ?? "") else {
            decisionHandler(.cancel)
            fail("The page returned an unsupported or unsuccessful response.")
            return
        }
        acceptedResponse = true
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard address != nil, let current = self.navigation, current === navigation, acceptedResponse else { return }
        deadline?.cancel()
        deadline = nil
        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        phase = .ready
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }

    private func navigationFailed(_ navigation: WKNavigation?, error: Error) {
        guard address != nil, let current = self.navigation, current === navigation else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        fail("The page could not load. Check your connection and retry.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard address != nil else { return }
        fail("The page stopped responding. Please retry.")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard address != nil, let url = navigationAction.request.url,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard isTrusted(origin, frame: frame) else { decisionHandler(.deny); return }
        let request = UUID()
        let revision = generation
        permissionReplies[request] = decisionHandler
        Task { @MainActor [weak self] in
            var allowed = true
            switch type {
            case .camera: allowed = await NanaMediaAuthorization.shared.authorize(.video)
            case .microphone: allowed = await NanaMediaAuthorization.shared.authorize(.audio)
            case .cameraAndMicrophone:
                let camera = await NanaMediaAuthorization.shared.authorize(.video)
                let microphone = await NanaMediaAuthorization.shared.authorize(.audio)
                allowed = camera && microphone
            @unknown default: allowed = false
            }
            guard let self, let reply = self.permissionReplies.removeValue(forKey: request) else { return }
            reply(allowed && self.generation == revision && self.isTrusted(origin, frame: frame) ? .grant : .deny)
        }
    }

    private func isTrusted(_ origin: WKSecurityOrigin, frame: WKFrameInfo) -> Bool {
        guard phase == .ready || phase == .loading else { return false }
        guard let address, frame.isMainFrame,
              let trusted = Self.origin(address), let currentURL = webView.url,
              Self.origin(currentURL) == trusted,
              let frameURL = frame.request.url, Self.origin(frameURL) == trusted else { return false }
        let scheme = origin.protocol.lowercased()
        let port = origin.port == 0 ? (scheme == "https" ? 443 : 80) : origin.port
        return "\(scheme)://\(origin.host.lowercased()):\(port)" == trusted
    }

    private static func origin(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host?.lowercased() else { return nil }
        return "\(scheme)://\(host):\(parts.port ?? (scheme == "https" ? 443 : 80))"
    }
}

@MainActor
private final class NanaMediaAuthorization {
    static let shared = NanaMediaAuthorization()
    private var requests: [String: Task<Bool, Never>] = [:]

    func authorize(_ type: AVMediaType) async -> Bool {
        if let request = requests[type.rawValue] { return await request.value }
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined:
            let request = Task { await AVCaptureDevice.requestAccess(for: type) }
            requests[type.rawValue] = request
            let allowed = await request.value
            requests[type.rawValue] = nil
            return allowed
        default: return false
        }
    }
}

@MainActor
final class NanaWebSurface: WKWebView {
    var onAttachmentChange: ((Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportAttachment()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportAttachment()
    }

    private func reportAttachment() {
        onAttachmentChange?(window != nil && bounds.width > 0 && bounds.height > 0)
    }
}
