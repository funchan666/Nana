import SwiftUI
import UIKit

final class NanaCaptureState: ObservableObject {
    static let shared = NanaCaptureState()
    @Published private(set) var isCaptured = false
    private var observer: NSObjectProtocol?
    private var sceneObservers: [NSObjectProtocol] = []

    private init() {
        isCaptured = UIScreen.screens.contains { $0.isCaptured }
        observer = NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isCaptured = UIScreen.screens.contains { $0.isCaptured }
        }
        sceneObservers = [
            NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] _ in self?.isCaptured = self?.isCaptured ?? false },
            NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in self?.isCaptured = UIScreen.screens.contains { $0.isCaptured } }
        ]
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        sceneObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

struct NanaPrivacyShield: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var captureState = NanaCaptureState.shared

    func body(content: Content) -> some View {
        ZStack {
            NanaSecureContentCanvas(content: content)
            if scenePhase != .active || captureState.isCaptured {
                Color.black.ignoresSafeArea().overlay {
                    Text("Nana is protected while this screen is unavailable.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(28)
                }
                .transition(.identity)
                .zIndex(100)
            }
        }
        .background(Color.black)
    }
}

private struct NanaSecureContentCanvas<Content: View>: UIViewControllerRepresentable {
    let content: Content
    func makeUIViewController(context: Context) -> NanaSecureHostingController<Content> { NanaSecureHostingController(rootView: content) }
    func updateUIViewController(_ controller: NanaSecureHostingController<Content>, context: Context) { controller.update(rootView: content) }
}

private final class NanaSecureHostingController<Content: View>: UIViewController {
    private let secureTextField = UITextField(frame: .zero)
    private let host: UIHostingController<Content>
    private var secureCanvas: UIView?
    private var didAttemptCanvas = false

    init(rootView: Content) {
        host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        secureTextField.isSecureTextEntry = true
        secureTextField.isUserInteractionEnabled = false
        secureTextField.backgroundColor = .clear
        view.addSubview(secureTextField)
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        secureTextField.frame = view.bounds
        if !didAttemptCanvas {
            didAttemptCanvas = true
            secureCanvas = secureTextField.subviews.first(where: { String(describing: type(of: $0)).contains("CanvasView") })
        }
        let canvasIsUsable = secureCanvas.map { $0.bounds.width > 1 && $0.bounds.height > 1 } == true
        let target: UIView
        if canvasIsUsable, let secureCanvas {
            target = secureCanvas
        } else {
            target = view
        }
        host.view.frame = target.bounds
        if host.view.superview !== target {
            host.view.removeFromSuperview()
            target.addSubview(host.view)
        }
    }

    func update(rootView: Content) { host.rootView = rootView; view.setNeedsLayout() }
}
