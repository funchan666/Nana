import SwiftUI
import WebKit
import Combine

enum AccountPolicyDocument: String, Identifiable {
    case userAgreement
    case privacyPolicy

    var id: String { rawValue }
    var title: String { self == .userAgreement ? "User Agreement" : "Privacy Policy" }
    var address: URL {
        switch self {
        case .userAgreement:
            return URL(string: "https://sites.google.com/view/nana-terms-of-service/future")!
        case .privacyPolicy:
            return URL(string: "https://sites.google.com/view/nana-privacy-policy/future")!
        }
    }
}

final class PolicyNavigationState: ObservableObject {
    @Published var isLoadingDocument = true
    @Published var documentLoadFailed = false
}

struct AccountPolicyBrowser: View {
    let document: AccountPolicyDocument
    @Environment(\.dismiss) private var dismiss
    @StateObject private var navigationState = PolicyNavigationState()
    @State private var reloadSequence = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }
                    .foregroundStyle(AccountEntryAppearance.linkLilac)
                    .frame(minWidth: 60, minHeight: 44)
                Spacer()
                Text(document.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Color.clear.frame(width: 60, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.top, 54)
            .padding(.bottom, 8)
            .background(Color(red: 0.085, green: 0.045, blue: 0.14))

            ZStack(alignment: .top) {
                PolicyWebContent(document: document, navigationState: navigationState, reloadSequence: reloadSequence)
                if navigationState.isLoadingDocument {
                    HStack(spacing: 12) {
                        AccountLoadingDots()
                        Text("Loading document…").font(.system(size: 13))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.085, green: 0.045, blue: 0.14))
                    .accessibilityElement(children: .combine)
                }
                if navigationState.documentLoadFailed {
                    VStack(spacing: 20) {
                        Spacer()
                        Text("Couldn't open this document")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Check your connection and try again.")
                            .font(.system(size: 14))
                            .foregroundStyle(AccountEntryAppearance.mutedText)
                        Button {
                            navigationState.documentLoadFailed = false
                            navigationState.isLoadingDocument = true
                            reloadSequence += 1
                        } label: {
                            Text("Try again")
                                .foregroundStyle(.white)
                                .padding(.horizontal, 30)
                                .frame(minHeight: 48)
                                .background(AccountEntryAppearance.violet, in: Capsule())
                        }
                        Spacer()
                    }
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                }
            }
        }
        .background(.black)
        .ignoresSafeArea(.container)
    }
}

private struct PolicyWebContent: UIViewRepresentable {
    let document: AccountPolicyDocument
    let navigationState: PolicyNavigationState
    let reloadSequence: Int

    func makeCoordinator() -> Coordinator { Coordinator(navigationState: navigationState) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedSequence != reloadSequence else { return }
        context.coordinator.loadedSequence = reloadSequence
        webView.load(URLRequest(url: document.address, timeoutInterval: 30))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let navigationState: PolicyNavigationState
        var loadedSequence = -1

        init(navigationState: PolicyNavigationState) {
            self.navigationState = navigationState
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            navigationState.isLoadingDocument = true
            navigationState.documentLoadFailed = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationState.isLoadingDocument = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            navigationState.isLoadingDocument = false
            navigationState.documentLoadFailed = true
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let destination = navigationAction.request.url,
                  ["https", "http"].contains(destination.scheme?.lowercased() ?? "") else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else {
                decisionHandler(.allow)
            }
        }

        private func reportFailure(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            navigationState.isLoadingDocument = false
            navigationState.documentLoadFailed = true
        }
    }
}
