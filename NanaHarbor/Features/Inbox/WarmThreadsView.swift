import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
import UIKit
#endif

struct WarmThreadsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedConversation: NanaConversation?
    @State private var showingCalls = false
    @State private var selectedProfile: NanaProfile?

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                if contentStore.payload.conversations.isEmpty && contentStore.state(for: .conversations) == .loading {
                    NanaScreenLoading(label: "Warming messages")
                } else if contentStore.payload.conversations.isEmpty, case .failed(let error) = contentStore.state(for: .conversations) {
                    NanaErrorState(title: "Messages are unavailable", detail: error.localizedDescription, actionTitle: "Retry") { Task { await contentStore.refresh(.conversations) } }
                } else { ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        quickLinks
                        NanaSectionTitle(eyebrow: "Your conversations", title: "Keep the thread warm")
                        if contentStore.payload.conversations.isEmpty {
                            NanaEmptyState(title: "No messages yet", detail: "A good room is a good place to start.", actionTitle: nil, action: nil)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(contentStore.payload.conversations.filter { !contentStore.blockedProfileIDs.contains($0.profileID) }) { conversation in
                                    Button { selectedConversation = conversation } label: { conversationRow(conversation) }
                                        .buttonStyle(.plain)
                                    if conversation.id != contentStore.payload.conversations.last?.id { Divider().overlay(NanaPalette.border) }
                                }
                            }
                            .padding(.horizontal, 15)
                            .nanaCard()
                        }
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                } }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await contentStore.refresh(.conversations) }
            .sheet(item: $selectedConversation) { conversation in NanaConversationView(conversation: conversation) }
            .sheet(isPresented: $showingCalls) {
                if let profile = contentStore.payload.profiles.first { NanaVideoCallView(profile: profile) }
                else { NanaUnavailableSurface(title: "Video calls are not available", detail: "The account and call services are not part of the published A-side contract yet.") }
            }
            .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MESSAGES")
                    .font(NanaType.stamp)
                    .tracking(1.4)
                    .foregroundStyle(NanaPalette.softPink)
                Text("People you can reach.")
                    .font(NanaType.hero)
                    .foregroundStyle(NanaPalette.warmWhite)
                Text("Keep the useful conversations close.")
                    .font(NanaType.body)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            Button { showingCalls = true } label: {
                Image(systemName: "video.fill")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(NanaPalette.neonPink, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var quickLinks: some View {
        HStack(spacing: 10) {
            messageShortcut(title: "New friends", icon: "person.2.fill", tint: NanaPalette.violet) { }
            messageShortcut(title: "System", icon: "bell.fill", tint: NanaPalette.neonPink) { }
            messageShortcut(title: "Calls", icon: "video.fill", tint: NanaPalette.deepSpace) { showingCalls = true }
        }
    }

    private func messageShortcut(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(tint, in: Circle())
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .nanaCard()
        }
        .buttonStyle(.plain)
    }

    private func conversationRow(_ conversation: NanaConversation) -> some View {
        HStack(spacing: 12) {
            NanaAvatarView(title: conversation.displayName, assetKey: conversation.avatarAssetKey, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(conversation.displayName)
                        .font(NanaType.bodyMedium)
                        .foregroundStyle(NanaPalette.warmWhite)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(NanaPalette.neonPink, in: Circle())
                    }
                }
                Text(conversation.preview)
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Text(conversation.sentAtLabel)
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NanaPalette.electricLilac)
            }
        }
        .padding(.vertical, 14)
    }
}

struct NanaConversationView: View {
    let conversation: NanaConversation
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var draft = ""
    @State private var showingCall = false

    private var messages: [NanaMessage] {
        contentStore.payload.messages.filter { $0.conversationID == conversation.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 13) {
                            NanaAvatarView(title: conversation.displayName, assetKey: conversation.avatarAssetKey, size: 72)
                            Text(conversation.displayName)
                                .font(NanaType.section)
                                .foregroundStyle(NanaPalette.warmWhite)
                            Text("A private conversation")
                                .font(NanaType.caption)
                                .foregroundStyle(NanaPalette.mutedWhite)
                            ForEach(messages) { message in
                                HStack {
                                    if message.isFromCurrentUser { Spacer(minLength: 60) }
                                    Text(message.body)
                                        .font(NanaType.body)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .background(message.isFromCurrentUser ? NanaPalette.violet : NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    if !message.isFromCurrentUser { Spacer(minLength: 60) }
                                }
                            }
                        }
                        .padding(20)
                    }
                    HStack(spacing: 8) {
                        TextField("Write a message…", text: $draft)
                            .foregroundStyle(.white)
                            .nanaGlassField()
                        Button {
                            contentStore.appendMessage(to: conversation.id, body: draft)
                            draft = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(NanaPalette.violet, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(NanaPalette.deepSpace.opacity(0.96))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCall = true } label: { Image(systemName: "video.fill").foregroundStyle(NanaPalette.neonPink) }
                }
            }
            .task { if conversation.id == "conversation-ava" { await contentStore.refresh(.avaMessages) } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
            .sheet(isPresented: $showingCall) {
                if let profile = contentStore.profile(with: conversation.profileID) { NanaVideoCallView(profile: profile) }
                else { NanaUnavailableSurface(title: "Video calls are not available", detail: "This profile is not in the current A-side snapshot.") }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaVideoCallView: View {
    let profile: NanaProfile
    @Environment(\.dismiss) private var dismiss
    @State private var callPhase = "Calling…"
    @State private var elapsed = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button("End") { dismiss() }
                        .font(NanaType.bodyMedium)
                        .foregroundStyle(NanaPalette.softPink)
                    Spacer()
                    Text(callPhase)
                        .font(NanaType.caption.weight(.semibold))
                        .foregroundStyle(NanaPalette.mutedWhite)
                    Spacer()
                    Text("0:\(String(format: "%02d", elapsed))")
                        .font(NanaType.caption.monospacedDigit())
                        .foregroundStyle(NanaPalette.mutedWhite)
                }
                .padding(.horizontal, 18)
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [NanaPalette.deepSpace, NanaPalette.midnight], startPoint: .top, endPoint: .bottom))
                        .overlay {
                            VStack(spacing: 10) {
                                NanaPlaceholderPortrait(title: profile.displayName, size: 96)
                                Text(profile.displayName)
                                    .font(NanaType.section)
                                    .foregroundStyle(.white)
                                Text(callPhase)
                                    .font(NanaType.caption)
                                    .foregroundStyle(NanaPalette.mutedWhite)
                            }
                        }
                    NanaSelfCameraPreview()
                        .frame(width: 112, height: 158)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.35), lineWidth: 1))
                        .padding(14)
                }
                .padding(.horizontal, 16)
                HStack(spacing: 18) {
                    CircleCallButton(icon: "mic.slash", title: "Mute") { }
                    CircleCallButton(icon: "video.slash", title: "Camera") { }
                    CircleCallButton(icon: "speaker.wave.2", title: "Speaker") { }
                    CircleCallButton(icon: "phone.down.fill", title: "End", tint: NanaPalette.warning) { dismiss() }
                }
                Text("The local preview waits for an answer. Real calling is not part of the published A-side contract.")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .task {
            for tick in 1...4 {
                try? await Task.sleep(for: .seconds(1))
                elapsed = tick
            }
            callPhase = "No answer"
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaUnavailableSurface: View {
    let title: String
    let detail: String
    var body: some View {
        ZStack {
            NanaBackdrop()
            NanaEmptyState(title: title, detail: detail, actionTitle: nil, action: nil)
                .padding(22)
        }
        .preferredColorScheme(.dark)
    }
}

private struct CircleCallButton: View {
    let icon: String
    let title: String
    var tint: Color = NanaPalette.cardStrong
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 49, height: 49)
                    .background(tint, in: Circle())
                Text(title)
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
        }
        .buttonStyle(.plain)
    }
}

#if canImport(AVFoundation)
private struct NanaSelfCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.start()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) { }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.stop()
    }
}

private final class CameraPreviewView: UIView {
    private let session = AVCaptureSession()

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    func start() {
        let previewLayer = layer as? AVCaptureVideoPreviewLayer
        previewLayer?.session = session
        previewLayer?.videoGravity = .resizeAspectFill
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else { return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in if granted { self?.configure() } }
        } else { configure() }
    }

    private func configure() {
        guard !session.isRunning, let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.addInput(input)
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
    }
}
#endif
