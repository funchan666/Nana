import SwiftUI
import AVKit
import UIKit

enum NanaAssetLibrary {
    private static let bundledPictures = resourceMap(extension: "jpg", directory: "pics", prefix: "nana.pic.")
    private static let bundledVideos = resourceMap(extension: "mp4", directory: "videos", prefix: "nana.video.")
    private static let bundledPhotoSlices = resourceMap(extension: "png", directory: "photos", prefix: "nana.photo.")
        .merging(resourceMap(extension: "png", directory: "assets/photos", prefix: "nana.photo."), uniquingKeysWith: { first, _ in first })
    private static let bundledVoiceSlices = resourceMap(extension: "png", directory: "voice-room-slices", prefix: "nana.voice.")

    private static func resourceMap(extension fileExtension: String, directory: String, prefix: String) -> [String: URL] {
        var files = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: directory) ?? []
        if files.isEmpty {
            let allFiles = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: nil) ?? []
            files = allFiles.filter { url in
                let path = url.path
                return path.contains("/\(directory)/") || (directory == "photos" && path.contains("/assets/photos/"))
            }
        }
        return Dictionary(files.map { (prefix + $0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func image(for assetKey: String) -> UIImage? {
        if assetKey.hasPrefix("nana.pic.") {
            guard let url = bundledPictures[assetKey] else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
        if assetKey.hasPrefix("nana.asset.") {
            return UIImage(named: String(assetKey.dropFirst("nana.asset.".count)))
        }
        if assetKey.hasPrefix("nana.photo."), let url = bundledPhotoSlices[assetKey] {
            return UIImage(contentsOfFile: url.path)
        }
        if assetKey.hasPrefix("nana.voice."), let url = bundledVoiceSlices[assetKey] {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(named: assetKey)
    }

    static func videoURL(for assetKey: String) -> URL? {
        bundledVideos[assetKey]
    }
}

struct NanaAssetImage: View {
    let assetKey: String
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let image = NanaAssetLibrary.image(for: assetKey) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                LinearGradient(
                    colors: [NanaPalette.neonPink.opacity(0.74), NanaPalette.violet, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct NanaVideoPreview: View {
    let assetKey: String
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                LinearGradient(
                    colors: [NanaPalette.neonPink.opacity(0.74), NanaPalette.violet, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task {
            guard player == nil, let url = NanaAssetLibrary.videoURL(for: assetKey) else { return }
            let configuredPlayer = AVPlayer(url: url)
            configuredPlayer.isMuted = true
            player = configuredPlayer
            configuredPlayer.play()
        }
    }
}

struct NanaMediaPreview: View {
    let assetKey: String

    var body: some View {
        if NanaAssetLibrary.videoURL(for: assetKey) != nil {
            NanaVideoPreview(assetKey: assetKey)
        } else {
            NanaAssetImage(assetKey: assetKey)
        }
    }
}

struct NanaAvatarView: View {
    let title: String
    let assetKey: String?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let assetKey, NanaAssetLibrary.image(for: assetKey) != nil {
                NanaAssetImage(assetKey: assetKey)
                    .scaledToFill()
            } else {
                NanaPlaceholderPortrait(title: title, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
    }
}
