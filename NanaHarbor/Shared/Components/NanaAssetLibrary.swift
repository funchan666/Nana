import SwiftUI
import AVKit
import UIKit

enum NanaAssetLibrary {
    private static let bundledPictures = resourceMap(extension: "jpg", directory: "pics", prefix: "nana.pic.")
    private static let bundledVideos = resourceMap(extension: "mp4", directory: "videos", prefix: "nana.video.")

    private static func resourceMap(extension fileExtension: String, directory: String, prefix: String) -> [String: URL] {
        let files = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: directory) ?? []
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
