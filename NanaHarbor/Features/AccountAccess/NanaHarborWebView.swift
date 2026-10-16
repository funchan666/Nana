import AVFoundation
import Combine
import SwiftUI
import WebKit
import OSLog

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
    private let mediaLog = Logger(subsystem: "com.nanalantern.harbortide", category: "WebMedia")
    private var previousAudioCategory: AVAudioSession.Category?
    private var mediaObservations: [NSKeyValueObservation] = []
    private var ownsPlaybackSuspension = false

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
        mediaObservations = [
            webView.observe(\.cameraCaptureState, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.logMediaState("camera-changed") }
            },
            webView.observe(\.microphoneCaptureState, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.logMediaState("microphone-changed") }
            }
        ]
        #if DEBUG
        webView.isInspectable = true
        #endif
    }

    func prepare(_ address: URL) {
        stop()
        self.address = address
        phase = .loading
        prepareAudioPlayback()
        let revision = generation
        armDeadline()
        ownsPlaybackSuspension = false
        webView.setAllMediaPlaybackSuspended(false) { [weak self] in
            guard let self, self.generation == revision, self.address == address else { return }
            self.mediaLog.notice("[WebMedia] Owned playback suspension released before load")
            self.navigation = self.webView.load(URLRequest(url: address, timeoutInterval: 30))
        }
    }

    func retry() {
        guard let address else { return }
        prepare(address)
    }

    func stop() {
        if address != nil { mediaLog.notice("[WebMedia] Document stopped; ending capture") }
        generation = UUID()
        deadline?.cancel()
        deadline = nil
        navigation = nil
        acceptedResponse = false
        address = nil
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        if !ownsPlaybackSuspension {
            ownsPlaybackSuspension = true
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }
        webView.setCameraCaptureState(.none, completionHandler: nil)
        webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        restoreAudioPlayback()
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
        phase = .ready
        logMediaState("document-ready")
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
            if address != nil {
                let mainFrame = navigationAction.targetFrame?.isMainFrame == true
                let blankFrame = navigationAction.request.url?.absoluteString == "about:blank"
                mediaLog.notice("[WebMedia] Navigation rejected mainFrame=\(mainFrame) aboutBlank=\(blankFrame)")
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        if let reason = captureRejectionReason(origin, frame: frame) {
            mediaLog.error("[WebMedia] Capture denied reason=\(reason, privacy: .public) type=\(type.rawValue) mainFrame=\(frame.isMainFrame)")
            decisionHandler(.deny)
            return
        }
        mediaLog.notice("[WebMedia] Capture requested type=\(type.rawValue) mainFrame=\(frame.isMainFrame)")
        logMediaState("permission-requested")
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
            let reason: String
            if self.generation != revision { reason = "stale-document" }
            else if !allowed { reason = "system-permission-denied" }
            else { reason = self.captureRejectionReason(origin, frame: frame) ?? "allowed" }
            let grant = reason == "allowed"
            self.mediaLog.notice("[WebMedia] Capture decision type=\(type.rawValue) allowed=\(grant) reason=\(reason, privacy: .public)")
            reply(grant ? .grant : .deny)
            self.logMediaState("permission-completed")
        }
    }

    private func captureRejectionReason(_ origin: WKSecurityOrigin, frame: WKFrameInfo) -> String? {
        guard phase == .ready || phase == .loading else { return "inactive-document" }
        guard let address, let trusted = Self.origin(address) else { return "missing-trusted-origin" }
        guard let currentURL = webView.url, Self.origin(currentURL) == trusted else { return "top-origin-mismatch" }
        guard Self.origin(frame.securityOrigin) == trusted else { return "frame-origin-mismatch" }
        guard Self.origin(origin) == trusted else { return "request-origin-mismatch" }
        return nil
    }

    private func logMediaState(_ event: String) {
        guard address != nil else { return }
        let camera = Self.captureStateName(webView.cameraCaptureState)
        let microphone = Self.captureStateName(webView.microphoneCaptureState)
        let cameraPermission = AVCaptureDevice.authorizationStatus(for: .video).rawValue
        let microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        let audio = AVAudioSession.sharedInstance()
        mediaLog.notice("[WebMedia] event=\(event, privacy: .public) camera=\(camera, privacy: .public) microphone=\(microphone, privacy: .public) cameraPermission=\(cameraPermission) microphonePermission=\(microphonePermission) attached=\(self.isAttached)")
        mediaLog.notice("[WebMedia] audio category=\(audio.category.rawValue, privacy: .public) mode=\(audio.mode.rawValue, privacy: .public) options=\(audio.categoryOptions.rawValue) inputCount=\(audio.currentRoute.inputs.count) outputCount=\(audio.currentRoute.outputs.count) volume=\(audio.outputVolume)")
        let revision = generation
        webView.requestMediaPlaybackState { [weak self] state in
            guard let self, self.generation == revision, self.address != nil else { return }
            let name: String
            switch state {
            case .none: name = "none"
            case .playing: name = "playing"
            case .paused: name = "paused"
            case .suspended: name = "suspended"
            @unknown default: name = "unknown"
            }
            self.mediaLog.notice("[WebMedia] event=\(event, privacy: .public) playback=\(name, privacy: .public)")
        }
    }

    private static func captureStateName(_ state: WKMediaCaptureState) -> String {
        switch state {
        case .none: return "none"
        case .active: return "active"
        case .muted: return "muted"
        @unknown default: return "unknown"
        }
    }

    private static func origin(_ origin: WKSecurityOrigin) -> String? {
        let scheme = origin.protocol.lowercased()
        guard ["https", "http"].contains(scheme), !origin.host.isEmpty else { return nil }
        let port = origin.port == 0 ? (scheme == "https" ? 443 : 80) : origin.port
        return "\(scheme)://\(origin.host.lowercased()):\(port)"
    }

    private func prepareAudioPlayback() {
        let session = AVAudioSession.sharedInstance()
        guard session.category == .ambient || session.category == .soloAmbient,
              session.mode == .default, session.categoryOptions.isEmpty else { return }
        let previous = session.category
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            previousAudioCategory = previous
        } catch {
            mediaLog.error("Playback audio configuration failed code=\((error as NSError).code)")
        }
    }

    private func restoreAudioPlayback() {
        guard let previous = previousAudioCategory else { return }
        previousAudioCategory = nil
        let session = AVAudioSession.sharedInstance()
        guard session.category == .playback, session.mode == .default,
              session.categoryOptions == [.mixWithOthers] else { return }
        do { try session.setCategory(previous, mode: .default, options: []) }
        catch { mediaLog.error("Playback audio cleanup failed code=\((error as NSError).code)") }
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
