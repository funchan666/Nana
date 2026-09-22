import SwiftUI
import Combine
import UIKit

/// Presentation-only session until an RTC service is available. It neither opens
/// capture devices nor changes server membership, gifts, followers or balances.
@MainActor
final class NanaVoiceConnectionSession: ObservableObject {
    enum Phase { case ready, waiting, connecting }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var waitingSeconds = 0
    @Published private(set) var connectionSeconds = 0
    @Published private(set) var queue: [NanaReplayAudienceMember] = []
    @Published var microphoneMuted = true
    @Published var cameraEnabled = false
    @Published var frontCamera = true

    var isActive: Bool { phase != .ready }
    var queuePosition: Int { queue.count + 1 }

    func request(audience: [NanaReplayAudienceMember]) {
        guard phase == .ready else { return }
        queue = Array(audience.prefix(2))
        waitingSeconds = 0
        connectionSeconds = 0
        phase = .waiting
    }

    // The owning room drives this clock only while visible and in the foreground.
    // Replacing these local transitions with RTC callbacks won't change the views.
    func advance() {
        switch phase {
        case .ready: break
        case .waiting:
            waitingSeconds += 1
            if waitingSeconds.isMultiple(of: 3) {
                if queue.isEmpty { phase = .connecting }
                else { queue.removeFirst() }
            }
        case .connecting: connectionSeconds += 1
        }
    }

    func end() {
        phase = .ready
        waitingSeconds = 0
        connectionSeconds = 0
        queue = []
        microphoneMuted = true
        cameraEnabled = false
        frontCamera = true
    }

    static func duration(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

struct NanaVoiceConnectionPanel: View {
    @ObservedObject var session: NanaVoiceConnectionSession
    @Binding var soundMuted: Bool
    let audience: [NanaReplayAudienceMember]
    let account: NanaAccountProfile?
    private let coral = Color(red: 1, green: 0.41, blue: 0.44)

    var body: some View {
        VStack(spacing: 16) {
            connectionBanner
            if session.phase == .connecting {
                connectionStatistics
                connectionControls
                Button { session.end() } label: {
                    Text("End the call").font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(coral, in: Capsule())
                }.buttonStyle(.plain)
            } else {
                queueList
            }
        }
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.2), value: session.phase)
    }

    private var connectionBanner: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 88)
            VStack(alignment: .leading, spacing: 7) {
                Text(bannerTitle).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(bannerSubtitle).font(.system(size: 11))
                    .foregroundStyle(Color.mint)
                if session.phase != .connecting {
                    Button {
                        if session.phase == .waiting { session.end() }
                        else { session.request(audience: audience) }
                    } label: {
                        Text(session.phase == .waiting ? "Cancel call" : "Request to join")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(session.phase == .waiting ? coral : NanaPalette.violet, in: Capsule())
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(minHeight: session.phase == .connecting ? 108 : 128)
        .background {
            GeometryReader { geometry in
                NanaAssetImage(assetKey: "nana.voice.voice_asset_078", contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.28))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if session.phase == .waiting {
                Text("Wait: \(NanaVoiceConnectionSession.duration(session.waitingSeconds))")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.mint).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.13), in: UnevenRoundedRectangle(bottomLeadingRadius: 8, topTrailingRadius: 12))
            }
        }
    }

    private var bannerTitle: String {
        switch session.phase {
        case .ready: return "Join the conversation"
        case .waiting: return "Waiting for connection"
        case .connecting: return "Connecting"
        }
    }

    private var bannerSubtitle: String {
        switch session.phase {
        case .ready: return "Take a seat with the host"
        case .waiting: return "Current queue: \(session.queuePosition)/20"
        case .connecting: return "Voice & video"
        }
    }

    private var queueList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.phase == .waiting ? "Waiting to join" : "In this room")
                Spacer()
                Text(session.phase == .waiting ? "\(session.queuePosition) in queue" : "\(audience.count) viewers")
            }
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            .padding(.bottom, 8)
            ForEach(Array(listMembers.enumerated()), id: \.element.id) { index, member in
                audienceRow(member, position: index + 1)
                Divider().overlay(.white.opacity(0.05))
            }
            if session.phase == .waiting {
                currentUserRow
            }
        }
    }

    private var listMembers: [NanaReplayAudienceMember] {
        session.phase == .waiting ? session.queue : Array(audience.prefix(4))
    }

    private func audienceRow(_ member: NanaReplayAudienceMember, position: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(position)").foregroundStyle(.white.opacity(0.5)).frame(width: 22)
            NanaAvatarView(title: member.displayName, assetKey: member.avatarAssetKey, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(session.phase == .waiting ? "Waiting" : "Viewer")
                    .font(.system(size: 10)).foregroundStyle(NanaPalette.softLilac)
            }
            Spacer(minLength: 4)
            if session.phase == .waiting {
                Text(NanaVoiceConnectionSession.duration(session.waitingSeconds))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.65))
            }
        }
        .font(.system(size: 12)).frame(minHeight: 58)
    }

    private var currentUserRow: some View {
        HStack(spacing: 10) {
            Text("\(session.queuePosition)").frame(width: 22).foregroundStyle(NanaPalette.softLilac)
            NanaVoiceConnectionAccountAvatar(account: account, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(account?.displayName ?? "You").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("You · Waiting").font(.system(size: 10)).foregroundStyle(NanaPalette.softLilac)
            }
            Spacer(minLength: 4)
            Text(NanaVoiceConnectionSession.duration(session.waitingSeconds))
                .font(.system(size: 10)).monospacedDigit()
        }
        .frame(minHeight: 58).padding(.horizontal, 4)
        .background(NanaPalette.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }

    private var connectionStatistics: some View {
        HStack(spacing: 10) {
            statistic("Call duration", value: NanaVoiceConnectionSession.duration(session.connectionSeconds), color: .green)
            statistic("New fans", value: "0", color: .cyan)
            statistic("Gifts received", value: "0", color: .orange)
        }
    }

    private func statistic(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionControls: some View {
        HStack(spacing: 10) {
            control(soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    title: soundMuted ? "Sound off" : "Sound on") { soundMuted.toggle() }
            control(session.cameraEnabled ? "video.fill" : "video.slash.fill",
                    title: session.cameraEnabled ? "Camera on" : "Camera off") { session.cameraEnabled.toggle() }
            control("arrow.triangle.2.circlepath.camera", title: session.frontCamera ? "Front camera" : "Back camera") {
                session.frontCamera.toggle()
            }
            .disabled(!session.cameraEnabled).opacity(session.cameraEnabled ? 1 : 0.4)
        }
    }

    private func control(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 19))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white.opacity(0.11), in: Capsule())
                Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            }
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

/// Uses profile portraits until media tracks arrive; never creates a second player.
struct NanaVoiceConnectionTiles: View {
    @ObservedObject var session: NanaVoiceConnectionSession
    let hostName: String
    let hostAvatar: String?
    let account: NanaAccountProfile?
    let openPanel: () -> Void

    var body: some View {
        Button(action: openPanel) {
            VStack(spacing: 6) {
                participantTile(title: hostName, symbol: "mic.fill") {
                    NanaAvatarView(title: hostName, assetKey: hostAvatar, size: 44)
                }
                participantTile(title: "You", symbol: session.microphoneMuted ? "mic.slash.fill" : "mic.fill") {
                    NanaVoiceConnectionAccountAvatar(account: account, size: 44)
                }
                Text(session.phase == .waiting ? "Waiting · \(session.queuePosition)" : NanaVoiceConnectionSession.duration(session.connectionSeconds))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .padding(.vertical, 5).frame(maxWidth: .infinity)
                    .background(NanaPalette.violet.opacity(0.8), in: Capsule())
            }
            .frame(width: 88)
        }.buttonStyle(.plain).accessibilityLabel("Open voice chat")
    }

    private func participantTile<Portrait: View>(title: String, symbol: String, @ViewBuilder portrait: () -> Portrait) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: symbol).font(.system(size: 9))
                Spacer()
                if title == "You" {
                    Image(systemName: session.cameraEnabled ? "video.fill" : "video.slash.fill")
                        .font(.system(size: 9))
                }
            }.foregroundStyle(.white.opacity(0.75))
            portrait()
            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .padding(8).frame(maxWidth: .infinity)
        .background(Color(red: 0.14, green: 0.12, blue: 0.20).opacity(0.93), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15), lineWidth: 0.5))
    }
}

private struct NanaVoiceConnectionAccountAvatar: View {
    let account: NanaAccountProfile?
    let size: CGFloat

    var body: some View {
        Group {
            if let data = account?.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NanaAvatarView(title: account?.displayName ?? "You", assetKey: nil, size: size)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
    }
}
