import SwiftUI
import AVFoundation
import Combine
import UIKit

struct NanaVideoPlayerView: View {
    let clip: NanaBundledVideo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var contentStore: NanaContentStore
    @StateObject private var playback = NanaVideoDetailPlayback()
    @State private var showingComment = false
    @State private var fillsScreen = true
    @State private var commentDraft = ""
    @State private var savedComment = false
    @FocusState private var commentFocused: Bool

    private var linkedPost: NanaPost? { contentStore.payload.posts.first { $0.coverAssetKey == clip.assetKey } }
    private var author: NanaProfile? { linkedPost.flatMap { contentStore.profile(with: $0.authorID) } }
    private var isLiked: Bool { contentStore.preference("video-like-\(clip.id)", default: false) }
    private var isSaved: Bool { contentStore.preference("video-save-\(clip.id)", default: false) }

    var body: some View {
        ZStack {
            videoBackground
            videoChrome
            if !playback.wantsToPlay && !playback.hasError {
                Button { playback.togglePlayback() } label: {
                    Image(systemName: "play.fill").font(.system(size: 27, weight: .semibold))
                        .frame(width: 68, height: 68)
                        .background(.black.opacity(0.36), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Play video")
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task(id: clip.id) {
            commentDraft = contentStore.draft(for: "video-comment-\(clip.id)")
            updatePlaybackActivity()
            await playback.load(NanaAssetLibrary.videoURL(for: clip.assetKey))
        }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, _ in updatePlaybackActivity() }
        .onChange(of: showingComment) { _, _ in updatePlaybackActivity() }
        .sheet(isPresented: $showingComment, onDismiss: { commentFocused = false }) { commentSheet }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private var videoBackground: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let player = playback.player {
                    NanaVideoDetailSurface(player: player, fillsScreen: fillsScreen)
                } else {
                    NanaMediaPreview(assetKey: clip.assetKey)
                }
                if playback.hasError {
                    VStack(spacing: 12) {
                        Text("Video unavailable").font(.system(size: 16, weight: .semibold))
                        Button("Try again") {
                            Task { await playback.load(NanaAssetLibrary.videoURL(for: clip.assetKey)) }
                        }
                        .padding(.horizontal, 20).frame(height: 44)
                        .background(NanaPalette.violet, in: Capsule())
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if !playback.hasError { playback.togglePlayback() } }
        }
        .ignoresSafeArea()
    }

    private var videoChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 24)
            HStack(alignment: .bottom, spacing: 14) {
                authorDetails
                Spacer(minLength: 0)
                interactionRail
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
            playbackTimeline
            commentEntry
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
        }
        .background {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.5), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.75), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea().allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Button { playback.stop(); dismiss() } label: {
                toolbarIcon("chevron.left")
            }.accessibilityLabel("Back")
            Spacer()
            VStack(spacing: 4) {
                Text("Video post").font(.system(size: 16, weight: .heavy).italic())
                Capsule().fill(NanaPalette.violet).frame(width: 22, height: 3)
            }
            Spacer()
            Button { playback.toggleMute() } label: {
                toolbarIcon(playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }.accessibilityLabel(playback.isMuted ? "Turn sound on" : "Mute video")
        }
        .buttonStyle(.plain).padding(.horizontal, 10).padding(.top, 4)
    }

    private func toolbarIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            .frame(width: 36, height: 36).background(.black.opacity(0.24), in: Circle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private var authorDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(linkedPost?.category ?? "VIDEO")
                .font(.system(size: 10, weight: .bold)).tracking(1)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(NanaPalette.violet.opacity(0.85), in: Capsule())
            HStack(spacing: 9) {
                authorImage
                VStack(alignment: .leading, spacing: 4) {
                    Text(author?.displayName ?? clip.creatorLabel)
                        .font(.system(size: 16, weight: .bold)).lineLimit(2)
                    Text(linkedPost?.publishedLabel ?? "Original video")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                }
            }
            if let linkedPost {
                Text(linkedPost.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if !linkedPost.body.isEmpty {
                    Text(linkedPost.body).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    @ViewBuilder private var authorImage: some View {
        if let author {
            NanaAvatarView(title: author.displayName, assetKey: author.avatarAssetKey, size: 40)
        } else {
            NanaMediaPreview(assetKey: clip.assetKey)
                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .accessibilityLabel("Video cover")
        }
    }

    private var interactionRail: some View {
        VStack(spacing: 14) {
            Button { contentStore.setPreference("video-like-\(clip.id)", value: !isLiked) } label: {
                railLabel(isLiked ? "heart.fill" : "heart", title: isLiked ? "Liked" : "Like", selected: isLiked)
            }.accessibilityHint("Saved on this device")
            Button { savedComment = false; showingComment = true } label: {
                railLabel("text.bubble", title: "Comment")
            }
            Button { contentStore.setPreference("video-save-\(clip.id)", value: !isSaved) } label: {
                railLabel(isSaved ? "bookmark.fill" : "bookmark", title: isSaved ? "Saved" : "Save", selected: isSaved)
            }.accessibilityHint("Saved on this device")
            if let url = NanaAssetLibrary.videoURL(for: clip.assetKey) {
                ShareLink(item: url) { railLabel("arrowshape.turn.up.right.fill", title: "Share") }
            }
        }
        .buttonStyle(.plain)
    }

    private func railLabel(_ symbol: String, title: String, selected: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 23, weight: .medium))
                .foregroundStyle(selected ? NanaPalette.neonPink : Color.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.23), in: Circle())
            Text(title).font(.system(size: 10, weight: .medium))
        }.frame(minWidth: 48).contentShape(Rectangle())
    }

    private var playbackTimeline: some View {
        VStack(spacing: 0) {
            Slider(value: $playback.scrubPosition, in: 0...max(playback.duration, 1), onEditingChanged: playback.scrub)
                .tint(NanaPalette.electricLilac)
                .disabled(playback.duration <= 0 || playback.hasError)
                .accessibilityLabel("Video progress")
            HStack(spacing: 8) {
                Button { playback.togglePlayback() } label: {
                    Image(systemName: playback.wantsToPlay ? "pause.fill" : "play.fill")
                        .font(.system(size: 12)).frame(width: 44, height: 44)
                }.accessibilityLabel(playback.wantsToPlay ? "Pause video" : "Play video")
                Text("\(timeLabel(playback.scrubPosition)) / \(timeLabel(playback.duration))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button { fillsScreen.toggle() } label: {
                    Label(fillsScreen ? "Full frame" : "Fill screen", systemImage: fillsScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium)).frame(minHeight: 44)
                }.accessibilityLabel(fillsScreen ? "Show the complete video frame" : "Fill the screen")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    private var commentEntry: some View {
        Button { savedComment = false; showingComment = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble").font(.system(size: 17))
                Text(commentDraft.isEmpty ? "Write a comment…" : "Continue your comment…")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "square.and.pencil").foregroundStyle(NanaPalette.electricLilac)
            }
            .padding(.horizontal, 14).frame(minHeight: 46)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        }.buttonStyle(.plain)
    }

    private var commentSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your comment").font(.system(size: 18, weight: .heavy).italic())
                Spacer()
                Button { saveCommentAndClose() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Save draft and close")
            }
            TextEditor(text: $commentDraft).scrollContentBackground(.hidden)
                .font(.system(size: 15)).padding(10).frame(height: 130)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .focused($commentFocused).accessibilityLabel("Comment draft")
            Text("Drafts stay on this device. Posting comments is not available yet.")
                .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            Button {
                savedComment = contentStore.saveDraft(commentDraft, for: "video-comment-\(clip.id)")
                commentFocused = false
            } label: {
                Text(savedComment ? "Draft saved" : "Save draft").font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48).background(NanaPalette.violet, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(20).foregroundStyle(.white).buttonStyle(.plain)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationBackground(NanaPalette.deepSpace)
        .interactiveDismissDisabled()
        .onChange(of: commentDraft) { _, text in
            commentDraft = String(text.prefix(500)); savedComment = false
        }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private func saveCommentAndClose() {
        guard contentStore.saveDraft(commentDraft, for: "video-comment-\(clip.id)") else { return }
        commentFocused = false
        showingComment = false
    }

    private func updatePlaybackActivity() {
        playback.setActive(scenePhase == .active && !showingComment)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@MainActor
private final class NanaVideoDetailPlayback: ObservableObject {
    @Published private(set) var player: AVQueuePlayer?
    @Published private(set) var wantsToPlay = true
    @Published private(set) var isMuted = false
    @Published private(set) var hasError = false
    @Published private(set) var duration: Double = 0
    @Published var scrubPosition: Double = 0
    private var looper: AVPlayerLooper?
    private var timeObserver: Any?
    private var isScrubbing = false
    private var isActive = true
    private var generation = UUID()

    func load(_ url: URL?) async {
        stop()
        let request = generation
        hasError = false
        guard let url else { hasError = true; return }
        let asset = AVURLAsset(url: url)
        do {
            let length = try await asset.load(.duration)
            guard !Task.isCancelled, request == generation else { return }
            guard length.seconds.isFinite, length.seconds > 0 else { hasError = true; return }
            duration = length.seconds
            let queue = AVQueuePlayer()
            queue.isMuted = isMuted
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset))
            player = queue
            timeObserver = queue.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == request, !self.isScrubbing, time.seconds.isFinite else { return }
                    self.scrubPosition = min(max(0, time.seconds), self.duration)
                }
            }
            resumeIfNeeded()
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            hasError = true
        }
    }

    func togglePlayback() { wantsToPlay.toggle(); resumeIfNeeded() }
    func toggleMute() { isMuted.toggle(); player?.isMuted = isMuted }
    func setActive(_ active: Bool) { isActive = active; resumeIfNeeded() }

    func scrub(_ editing: Bool) {
        isScrubbing = editing
        if editing { player?.pause(); return }
        let request = generation
        player?.seek(to: CMTime(seconds: scrubPosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == request else { return }
                self.resumeIfNeeded()
            }
        }
    }

    private func resumeIfNeeded() {
        if isActive && wantsToPlay && !isScrubbing { player?.play() }
        else { player?.pause() }
    }

    func stop() {
        generation = UUID()
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        duration = 0
        scrubPosition = 0
        isScrubbing = false
    }
}

private struct NanaVideoDetailSurface: UIViewRepresentable {
    let player: AVPlayer
    let fillsScreen: Bool
    func makeUIView(context: Context) -> NanaVideoDetailLayerView {
        let view = NanaVideoDetailLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fillsScreen ? .resizeAspectFill : .resizeAspect
        return view
    }
    func updateUIView(_ view: NanaVideoDetailLayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fillsScreen ? .resizeAspectFill : .resizeAspect
    }
    static func dismantleUIView(_ view: NanaVideoDetailLayerView, coordinator: ()) { view.playerLayer.player = nil }
}

private final class NanaVideoDetailLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
