import SwiftUI
import AVKit
import UIKit

enum NanaAssetLibrary {
    static func clearVideoCoverCache() { videoCoverCache.removeAllObjects() }
    private static let videoCoverCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    private static let bundledPictures = resourceMap(extension: "jpg", directory: "pics", prefix: "nana.pic.")
    private static let bundledVideoCovers = resourceMap(extension: "jpg", directory: "videos/covers", prefix: "nana.video.")
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
        if assetKey.hasPrefix("nana.video.") {
            return videoCover(for: assetKey)
        }
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

    // User-approved sample portraits for bundled creators without a supplied profile photo.
    // Key by creator handle so multiple clips and saved identities keep the same portrait.
    static func sampleCreatorPortrait(for handle: String) -> String? {
        let portraits = [
            "@ariffathulhakim": "DdUCdcjCBlJ",
            "@berniemor": "DdTNJvtjogw",
            "@capt.carterbrown": "DdE-UZfnG_R",
            "@coletrotta": "DdRrLB4DED5",
            "@escapetolandscapes": "DdBLxdkjQZi",
            "@harvon.x": "DcuZZmSliO1",
            "@iangblack": "Dcz55LfiUxQ",
            "@inga_galeeva": "Dc2AwHAjPnJ",
            "@josee.steelman": "DdOkklBgBAh",
            "@lilyrowland1": "DdeJda-FZ6L",
            "@maialopezr": "DdV5DG4DAsC",
            "@mark_pnw": "DdZdzhTjEWz",
            "@matti_af": "DctrZb7jKiH",
            "@megaamerican": "DcuIUt0EfAG",
            "@mickjaggedd": "DdTY1ZoDJ_o",
            "@mkaaloha": "DdT-9kziCLE",
            "@radovantravels": "DdbslWbiDao"
        ]
        return portraits[handle.lowercased()].map { "nana.pic." + $0 }
    }

    /// Every supplied video participates in the feed, independent of the server's room count.
    static var videoClips: [NanaBundledVideo] {
        bundledVideos.keys.sorted().map { NanaBundledVideo(assetKey: $0) }
    }

    static func videoCover(for assetKey: String) -> UIImage? {
        if let cached = videoCoverCache.object(forKey: assetKey as NSString) { return cached }
        guard let url = bundledVideoCovers[assetKey], let image = UIImage(contentsOfFile: url.path) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        videoCoverCache.setObject(image, forKey: assetKey as NSString, cost: cost)
        return image
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

struct NanaBundledVideo: Identifiable {
    let assetKey: String
    var id: String { assetKey }
    var creatorLabel: String {
        let filename = String(assetKey.dropFirst("nana.video.".count))
        // Supplied filenames end in an underscore followed by the 11-character media ID.
        return "@" + String(filename.dropLast(12)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

/// Static covers only. Video playback belongs to the presented player, never feed cells.
struct NanaMediaPreview: View {
    let assetKey: String

    var body: some View {
        GeometryReader { geometry in
            Group {
                if NanaAssetLibrary.videoURL(for: assetKey) != nil {
                    if let image = NanaAssetLibrary.videoCover(for: assetKey) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        NanaPalette.deepSpace
                    }
                } else {
                    NanaAssetImage(assetKey: assetKey)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            // Aspect-fill cropping does not constrain hit testing by itself.
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
    }
}

/// The account's selected photo always takes precedence over the bundled default.
struct NanaAccountAvatarView: View {
    let data: Data?
    var size: CGFloat = 72
    static let defaultAssetKey = "nana.pic.DdV5vxnEs3N"

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NanaAssetImage(assetKey: Self.defaultAssetKey)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
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
