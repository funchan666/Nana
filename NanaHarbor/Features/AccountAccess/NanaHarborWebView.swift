import SwiftUI
import WebKit
import AVFoundation

struct NanaHarborWebView: View {
    let address: URL
    let close: () -> Void
    @State private var didFinish = false
    @State private var failed = false

    var body: some View {
        ZStack {
            NanaProtectedWebDocument(address: address, didFinish: $didFinish, failed: $failed)
                .ignoresSafeArea()
            if failed {
                VStack(spacing: 14) {
                    Text("This harbor could not open")
                        .font(.title3.weight(.semibold))
                    Text("Return to Nana and try again when the service is ready.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Button("Return") { close() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(28)
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
                .padding(24)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

private struct NanaProtectedWebDocument: UIViewRepresentable {
    let address: URL
    @Binding var didFinish: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(didFinish: $didFinish, failed: $failed) }
    func makeUIView(context: Context) -> UIView { context.coordinator.makeView(address: address) }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.loadIfNeeded(address: address) }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let didFinish: Binding<Bool>
        private let failed: Binding<Bool>
        private var loadedAddress: URL?
        private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        init(didFinish: Binding<Bool>, failed: Binding<Bool>) { self.didFinish = didFinish; self.failed = failed }
        func makeView(address: URL) -> UIView {
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = .black
            loadIfNeeded(address: address)
            return webView
        }
        func loadIfNeeded(address: URL) {
            guard loadedAddress != address else { return }
            loadedAddress = address
            didFinish.wrappedValue = false
            failed.wrappedValue = false
            webView.load(URLRequest(url: address, timeoutInterval: 30))
        }
        func stop() { webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didFinish.wrappedValue = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed.wrappedValue = true }

        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let host = origin.host.lowercased()
            guard host == "nanacc.top" || host.hasSuffix(".nanacc.top") else { decisionHandler(.deny); return }
            Task { @MainActor in
                let cameraNeeded = type == .camera || type == .cameraAndMicrophone
                let microphoneNeeded = type == .microphone || type == .cameraAndMicrophone
                var allowed = true
                if cameraNeeded {
                    allowed = allowed && await Self.requestAccess(for: .video)
                }
                if microphoneNeeded {
                    allowed = allowed && await Self.requestAccess(for: .audio)
                }
                decisionHandler(allowed ? .grant : .deny)
            }
        }

        @available(iOS 15.0, *)
        private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: mediaType) {
            case .authorized: return true
            case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
            default: return false
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
