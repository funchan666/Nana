import SwiftUI
import AVFoundation
import Combine
import UIKit

extension View {
    func nanaVideoCall(profile: Binding<NanaProfile?>) -> some View {
        modifier(NanaVideoCallPresentation(profile: profile))
    }
}

/// Every entry point uses the same gate; merely opening it never requests camera access.
private struct NanaVideoCallPresentation: ViewModifier {
    @Binding var profile: NanaProfile?
    @EnvironmentObject private var contentStore: NanaContentStore

    private var canCall: Bool {
        profile.map { contentStore.canStartVideoCall(with: $0.id) } ?? false
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(profile != nil && !canCall)
            .overlay {
                if let profile, !canCall {
                    NanaMutualCallNotice(profile: profile) { self.profile = nil }
                        .zIndex(100)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { profile != nil && canCall },
                set: { if !$0 { profile = nil } }
            )) {
                if let profile {
                    NanaVideoCallView(profile: profile, accountID: contentStore.accountScope)
                }
            }
            .onChange(of: contentStore.accountScope) { _, _ in profile = nil }
    }
}

private struct NanaMutualCallNotice: View {
    let profile: NanaProfile
    let close: () -> Void
    @EnvironmentObject private var contentStore: NanaContentStore
    private var following: Bool { contentStore.isFollowing(profile.id) }
    private var unavailable: Bool {
        contentStore.accountScope == nil || contentStore.hiddenAuthorIDs.contains(profile.id)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea().onTapGesture(perform: close)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Image("NanaMutualCallIllustration").resizable().scaledToFit()
                        .frame(width: 142, height: 122).accessibilityHidden(true)
                    Text("BETTER WHEN IT'S MUTUAL")
                        .font(.system(size: 10, weight: .bold)).tracking(1.8)
                        .foregroundStyle(NanaPalette.electricLilac)
                    Text(unavailable ? "Call unavailable" : "Follow each other first")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    HStack(spacing: 8) {
                        NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 32)
                        Text(profile.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    }
                    Text(unavailable
                         ? "Sign in and unblock this person before starting a video call."
                         : "Video calls are for mutual followers. Once you both follow each other, you can start here.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                    if following && !unavailable {
                        Text("You're following · Waiting for their follow-back")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(NanaPalette.electricLilac)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        if !following && !unavailable { contentStore.toggleConnection(for: profile) }
                        else { close() }
                    } label: {
                        Text(!following && !unavailable ? "Follow" : "Got it")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background { Image("NanaCheckInGuideButton").resizable() }
                    }.buttonStyle(.plain).padding(.top, 4)
                    Button("Not now", action: close).font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.65)).frame(minHeight: 44).buttonStyle(.plain)
                }
                .multilineTextAlignment(.center).foregroundStyle(.white)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 12)
            }
            .frame(maxWidth: 352).frame(maxHeight: 510)
            .background { Image("NanaSettingsCardSurface").resizable() }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// This is a cancellable local waiting room, not a simulated remote connection.
/// No signaling or media transport is provided by the current service.
struct NanaVideoCallView: View {
    let profile: NanaProfile
    let accountID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var contentStore: NanaContentStore
    @StateObject private var camera = NanaLocalCallCamera()

    private var permitted: Bool {
        accountID != nil && accountID == contentStore.accountScope
            && contentStore.canStartVideoCall(with: profile.id)
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                NanaAssetImage(assetKey: profile.avatarAssetKey ?? "nana.asset.NanaMutualCallIllustration", contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped().blur(radius: 26).scaleEffect(1.15)
            }.ignoresSafeArea().allowsHitTesting(false)
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: endCall) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_030", contentMode: .fit)
                            .frame(width: 26, height: 26).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("End call and go back")
                    Text("Video call").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("PRIVATE PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.horizontal, 14)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        HStack { Spacer(); localPreview }.padding(.top, 12)
                        recipient.padding(.top, 12)
                        VStack(spacing: 9) {
                            Text("Waiting to connect…").font(.system(size: 17, weight: .medium))
                            Text("Local preview only. Your camera stays on this device.\nThe other person hasn't been called.")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.68))
                                .lineSpacing(3).multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                }
                .clipped()
                controls.padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 20)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            guard permitted else { dismiss(); return }
            camera.resume()
        }
        .onChange(of: permitted) { _, allowed in
            if !allowed { endCall() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && permitted { camera.resume() }
            else if phase == .inactive { camera.pauseForInactiveScene() }
            else { camera.suspend() }
        }
        .onDisappear { camera.suspend() }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureSessionWasInterrupted, object: camera.session).receive(on: DispatchQueue.main)) { _ in
            camera.suspend()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureSessionInterruptionEnded, object: camera.session).receive(on: DispatchQueue.main)) { _ in
            if scenePhase == .active && permitted { camera.resume() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureSessionRuntimeError, object: camera.session).receive(on: DispatchQueue.main)) { _ in
            camera.captureFailed()
        }
    }

    private var recipient: some View {
        VStack(spacing: 16) {
            NanaAssetImage(assetKey: profile.avatarAssetKey ?? "nana.asset.NanaMutualCallIllustration", contentMode: .fill)
                .frame(width: 114, height: 142).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 21))
                .overlay { RoundedRectangle(cornerRadius: 21).strokeBorder(NanaPalette.violet, lineWidth: 1.5) }
            Text(profile.displayName).font(.system(size: 23, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center).lineLimit(2)
            if profile.hasCompleteDetails != false {
                Text([profile.age > 0 ? "\(profile.age)" : "", profile.region,
                      profile.level > 0 ? "Lv.\(profile.level)" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            Text("Mutual followers").font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background { Image("NanaCheckInGuideButton").resizable() }
        }
    }

    private var localPreview: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.black.opacity(0.4)
                NanaCallCameraPreview(session: camera.session, mirrored: camera.isFrontCamera)
                    .opacity(camera.state == .ready ? 1 : 0)
                if camera.state != .ready {
                    VStack(spacing: 6) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_162", contentMode: .fit)
                            .frame(width: 30, height: 30)
                        Text(camera.state == .denied ? camera.permissionExplanation : camera.state.label).font(.system(size: 11)).multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                        if camera.state == .denied {
                            Button("Settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }.font(.system(size: 11, weight: .semibold)).frame(minHeight: 44)
                        } else if camera.state == .unavailable {
                            Button("Retry") { camera.resume() }
                                .font(.system(size: 11, weight: .semibold)).frame(minHeight: 44)
                        }
                    }
                }
            }
            .frame(width: 108, height: 148).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 1) }
            Text("Only you can see this").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
        }
    }

    private var controls: some View {
        HStack(alignment: .top) {
            callControl("156", label: "Flip", size: 54) { camera.flip() }
                .disabled(camera.state != .ready).opacity(camera.state == .ready ? 1 : 0.4)
            Spacer(minLength: 16)
            callControl("165", label: "End call", size: 72, action: endCall)
            Spacer(minLength: 16)
            callControl("162", label: camera.wantsCamera ? "Camera off" : "Camera on", size: 54) { camera.toggle() }
        }
    }

    private func callControl(_ asset: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_\(asset)", contentMode: .fit)
                    .frame(width: size, height: size).frame(height: 72)
                Text(label).font(.system(size: 11, weight: .medium))
            }.frame(minWidth: 64).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func endCall() { camera.suspend(); dismiss() }
}
