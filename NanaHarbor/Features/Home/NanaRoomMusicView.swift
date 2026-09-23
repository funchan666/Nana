import SwiftUI
import AVFoundation
import Combine

struct NanaRoomMusicTrack: Identifiable {
    let id: String
    let title: String
    let mood: String

    static let library: [NanaRoomMusicTrack] = [
        .init(id: "moonlit-keys", title: "Moonlit Keys", mood: "Soft keys · Nighttime"),
        .init(id: "slow-sunday", title: "Slow Sunday", mood: "Mellow beats · Unwind"),
        .init(id: "city-lights", title: "City Lights", mood: "Warm groove · Catch up"),
        .init(id: "quiet-tides", title: "Quiet Tides", mood: "Ambient · Slow down"),
        .init(id: "little-sparks", title: "Little Sparks", mood: "Bright keys · Create"),
        .init(id: "after-hours", title: "After Hours", mood: "Soft beats · Late talks")
    ]
}

/// One local music player per room. Track changes replace playback, never layer it.
@MainActor
final class NanaRoomMusicPlayer: ObservableObject {
    @Published private(set) var selectedTrack: NanaRoomMusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    @Published var volume: Double = 0.45 {
        didSet { updateVolume() }
    }
    private var audio: AVAudioPlayer?
    private var isMuted = false

    func toggle(_ track: NanaRoomMusicTrack) {
        errorMessage = nil
        if selectedTrack?.id == track.id, isPlaying {
            pause()
            return
        }
        do {
            let next: AVAudioPlayer
            if selectedTrack?.id == track.id, let audio {
                next = audio
            } else {
                guard let url = Bundle.main.url(forResource: track.id, withExtension: "m4a", subdirectory: "room-music") else {
                    errorMessage = "This track couldn't be opened. Please choose another track."
                    return
                }
                next = try AVAudioPlayer(contentsOf: url)
                next.numberOfLoops = -1
                guard next.prepareToPlay() else {
                    errorMessage = "This track couldn't be prepared. Please try again."
                    return
                }
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            audio?.pause()
            isPlaying = false
            next.volume = isMuted ? 0 : Float(volume)
            guard next.play() else {
                if audio == nil {
                    try? session.setActive(false, options: .notifyOthersOnDeactivation)
                }
                errorMessage = "Music couldn't start. Tap the track to try again."
                return
            }
            audio = next
            selectedTrack = track
            isPlaying = true
        } catch {
            errorMessage = "Music couldn't start. Please try again."
        }
    }

    func pause() {
        audio?.pause()
        isPlaying = false
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        updateVolume()
    }

    func stop() {
        let hadPlayer = audio != nil
        audio?.stop()
        audio = nil
        selectedTrack = nil
        isPlaying = false
        errorMessage = nil
        if hadPlayer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func updateVolume() { audio?.volume = isMuted ? 0 : Float(volume) }
}

struct NanaRoomMusicPanel: View {
    @ObservedObject var player: NanaRoomMusicPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A little music for the conversation")
                .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            volumeControl
            if let error = player.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(NanaPalette.softPink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(NanaRoomMusicTrack.library) { track in
                trackRow(track)
            }
            if player.selectedTrack != nil {
                Button("Stop music") { player.stop() }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain)
            }
            Text("Music keeps playing when you close this panel.")
                .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                .foregroundStyle(NanaPalette.electricLilac).accessibilityHidden(true)
            Slider(value: $player.volume, in: 0...1)
                .tint(NanaPalette.violet).accessibilityLabel("Music volume")
            Text("\(Int(player.volume * 100))%")
                .font(.system(size: 11)).monospacedDigit().frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(minHeight: 48)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func trackRow(_ track: NanaRoomMusicTrack) -> some View {
        let selected = player.selectedTrack?.id == track.id
        let playing = selected && player.isPlaying
        return Button { player.toggle(track) } label: {
            HStack(spacing: 10) {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_065", contentMode: .fit)
                    .frame(width: 46, height: 46).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(selected ? (playing ? "Now playing" : "Paused") : track.mood)
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? NanaPalette.electricLilac : NanaPalette.mutedWhite)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 4) {
                    Text("Free").font(.system(size: 10, weight: .medium)).foregroundStyle(.mint)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 44, height: 28)
                        .background(NanaPalette.violet, in: Capsule())
                }
            }
            .padding(10).frame(minHeight: 76)
            .background(selected ? NanaPalette.violet.opacity(0.17) : .white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? NanaPalette.electricLilac.opacity(0.65) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(playing ? "Pause" : "Play") \(track.title), free")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
