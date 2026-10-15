import SwiftUI
import AVKit
import UIKit

enum NanaAssetLibrary {
    @MainActor static func clearVideoCoverCache() { NanaRemoteImageStore.shared.clear() }

    static func hasImageSource(for assetKey: String) -> Bool {
        NanaRemoteMedia.source(for: assetKey) != nil || image(for: assetKey) != nil
    }

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
        if NanaRemoteMedia.source(for: assetKey) != nil { return nil }
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

    static var videoClips: [NanaBundledVideo] {
        NanaRemoteMedia.entries.filter { $0.kind == .video }
            .sorted { $0.assetKey < $1.assetKey }.map { NanaBundledVideo(assetKey: $0.assetKey) }
    }

    static func videoURL(for assetKey: String) -> URL? {
        guard let source = NanaRemoteMedia.source(for: assetKey), source.kind == .video else { return nil }
        return source.url
    }
}

struct NanaAssetImage: View {
    let assetKey: String
    var contentMode: ContentMode = .fill
    @State private var remoteImage: UIImage?
    @State private var loadedAssetKey: String?

    var body: some View {
        Group {
            if let image = NanaAssetLibrary.image(for: assetKey) ?? (loadedAssetKey == assetKey ? remoteImage : nil) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if NanaAssetLibrary.videoURL(for: assetKey) != nil {
                NanaPalette.deepSpace
            } else {
                LinearGradient(
                    colors: [NanaPalette.neonPink.opacity(0.74), NanaPalette.violet, .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task(id: assetKey) {
            loadedAssetKey = nil
            remoteImage = nil
            guard let source = NanaRemoteMedia.source(for: assetKey) else { return }
            let image = await NanaRemoteImageStore.shared.image(for: source)
            guard !Task.isCancelled else { return }
            remoteImage = image
            loadedAssetKey = assetKey
        }
    }
}

struct NanaBundledVideo: Identifiable {
    let assetKey: String
    var id: String { assetKey }
    var creatorLabel: String {
        let filename = String(assetKey.dropFirst("nana.video.".count))
        return "@" + String(filename.dropLast(12)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

struct NanaMediaPreview: View {
    let assetKey: String

    var body: some View {
        GeometryReader { geometry in
            NanaAssetImage(assetKey: assetKey)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
    }
}

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
            if let assetKey, NanaAssetLibrary.hasImageSource(for: assetKey) {
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
