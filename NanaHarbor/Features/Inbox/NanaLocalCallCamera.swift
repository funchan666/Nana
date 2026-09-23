import SwiftUI
@preconcurrency import AVFoundation
import Combine
import UIKit

@MainActor
final class NanaLocalCallCamera: ObservableObject {
    enum State: Equatable {
        case preparing, ready, off, paused, denied, unavailable

        var label: String {
            switch self {
            case .preparing: return "Preparing preview…"
            case .ready: return "You"
            case .off: return "Camera is off"
            case .paused: return "Preview paused"
            case .denied: return "Permissions needed"
            case .unavailable: return "Camera unavailable"
            }
        }
    }

    @Published private(set) var state: State = .preparing
    @Published private(set) var wantsCamera = true
    @Published private(set) var isFrontCamera = true
    @Published private(set) var permissionExplanation = "Allow camera and microphone access."
    private var authorizationTask: Task<Void, Never>?
    private let capture = NanaCallCaptureSession()
    private var revision = UUID()
    private var active = false
    var session: AVCaptureSession { capture.session }

    func resume() {
        active = true
        guard wantsCamera else { state = .off; return }
        // Permission dialogs temporarily deactivate the scene. Resume must not issue duplicate requests.
        guard authorizationTask == nil else { return }
        let request = UUID()
        revision = request
        state = .preparing
        authorizationTask = Task { [weak self] in
            let missing = await NanaMediaPermissions.request(video: true, audio: true)
            guard !Task.isCancelled, let self, self.revision == request else { return }
            self.authorizationTask = nil
            guard missing.isEmpty else {
                self.capture.stop()
                self.permissionExplanation = "Allow " + missing.joined(separator: " and ").lowercased() + " access."
                self.state = .denied
                return
            }
            guard self.active, self.wantsCamera else { return }
            self.capture.start(front: self.isFrontCamera) { [weak self] succeeded in
                Task { @MainActor [weak self] in
                    guard let self, self.active, self.wantsCamera, self.revision == request else { return }
                    self.state = succeeded ? .ready : .unavailable
                }
            }
        }
    }

    /// A system permission dialog pauses frames but keeps the sequential permission request alive.
    func pauseForInactiveScene() {
        active = false
        capture.stop()
        if state == .ready { state = .paused }
    }

    func suspend() {
        active = false
        revision = UUID()
        authorizationTask?.cancel()
        authorizationTask = nil
        capture.stop()
        state = wantsCamera ? .paused : .off
    }

    func captureFailed() {
        suspend()
        state = .unavailable
    }

    func toggle() {
        wantsCamera.toggle()
        if wantsCamera { resume() }
        else { suspend() }
    }

    func flip() {
        guard active, wantsCamera, state == .ready else { return }
        isFrontCamera.toggle()
        resume()
    }
}

/// All capture configuration, start and stop operations run on one serial queue.
/// No audio input or recording/network output is attached: frames only reach the preview layer.
private final class NanaCallCaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.nana.video-call.camera", qos: .userInitiated)
    private var currentInput: AVCaptureDeviceInput?

    func start(front: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            let position: AVCaptureDevice.Position = front ? .front : .back
            if currentInput?.device.position != position {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    if session.isRunning { session.stopRunning() }
                    completion(false)
                    return
                }
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration()
                if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                let previous = currentInput
                if let previous { session.removeInput(previous) }
                guard session.canAddInput(input) else {
                    if let previous, session.canAddInput(previous) { session.addInput(previous) }
                    session.commitConfiguration()
                    completion(false)
                    return
                }
                session.addInput(input)
                currentInput = input
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

struct NanaCallCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeUIView(context: Context) -> NanaCallPreviewSurface {
        let view = NanaCallPreviewSurface()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: NanaCallPreviewSurface, context: Context) {
        guard let connection = uiView.previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    static func dismantleUIView(_ uiView: NanaCallPreviewSurface, coordinator: ()) {
        uiView.previewLayer.session = nil
    }
}

final class NanaCallPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
