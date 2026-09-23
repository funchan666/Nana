import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import UIKit

enum NanaMediaPermissions {
    /// Ask only for devices needed by the chosen action. Never request library-wide access.
    static func request(video: Bool, audio: Bool) async -> [String] {
        var missing: [String] = []
        for (needed, type, label) in [(video, AVMediaType.video, "Camera"), (audio, AVMediaType.audio, "Microphone")] {
            guard !Task.isCancelled else { return missing }
            guard needed else { continue }
            let status = AVCaptureDevice.authorizationStatus(for: type)
            let allowed: Bool
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: type) }
            else { allowed = status == .authorized }
            if !allowed { missing.append(label) }
        }
        return missing
    }
}

final class NanaPickedMedia: Identifiable {
    enum Content { case photo(Data), video(URL) }
    let id = UUID()
    let content: Content
    init(content: Content) { self.content = content }
    deinit { discard() }
    var photoData: Data? { if case .photo(let data) = content { return data }; return nil }
    var title: String { if case .photo = content { return "Photo attachment" }; return "Video attachment" }
    func discard() {
        // A video always owns a copied temporary file, never a Photos-library original.
        if case .video(let url) = content { try? FileManager.default.removeItem(at: url) }
    }
}

enum NanaMediaSourceKind { case photos, photosAndVideos }
private enum NanaCaptureKind: String, Identifiable { case photo, video; var id: String { rawValue } }
private enum NanaMediaPickResult { case selected(NanaPickedMedia), cancelled, failed(String) }

extension View {
    func nanaMediaSource(isPresented: Binding<Bool>, kind: NanaMediaSourceKind = .photos,
                         onSelect: @escaping (NanaPickedMedia) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            NanaMediaSourcePicker(kind: kind, onSelect: onSelect)
                .presentationDetents([.height(kind == .photos ? 340 : 420)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(NanaPalette.deepSpace)
        }
    }
}

private struct NanaMediaSourcePicker: View {
    let kind: NanaMediaSourceKind
    let onSelect: (NanaPickedMedia) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var capture: NanaCaptureKind?
    @State private var showingLibrary = false
    @State private var requestingPermission = false
    @State private var importing = false
    @State private var importProgress: Progress?
    @State private var libraryDismissed = false
    @State private var permissionTask: Task<Void, Never>?
    @State private var error: String?
    @State private var needsSettings = false
    @State private var pending: NanaPickedMedia?
    @State private var active = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add media").font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                Button("Cancel") { permissionTask?.cancel(); importProgress?.cancel(); dismiss() }
                    .font(.system(size: 14)).frame(minHeight: 44)
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(NanaPalette.softPink)
                if needsSettings {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }.font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
                }
            } else {
                Text(importing ? "Preparing your media…" : (requestingPermission ? "Checking permissions…" : "Choose how you'd like to add it."))
                    .font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    choice("Take photo", subtitle: "Use your camera", asset: "nana.voice.voice_asset_156") { openCamera(.photo) }
                    if kind == .photosAndVideos {
                        choice("Record video", subtitle: "Up to 60 sec · With sound", asset: "nana.voice.voice_asset_162") { openCamera(.video) }
                    }
                    choice("Photo library", subtitle: kind == .photos ? "Choose a photo" : "Choose a photo or video",
                           asset: "nana.asset.NanaChatPhotoIcon") { error = nil; needsSettings = false; libraryDismissed = false; showingLibrary = true }
                }
            }.disabled(requestingPermission || importing)
        }
        .foregroundStyle(.white).padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
        .background { Image("NanaSettingsCardSurface").resizable().ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $capture, onDismiss: deliverSelection) { source in
            NanaCameraMediaPicker(kind: source) { result in
                accept(result)
                capture = nil
            }.ignoresSafeArea()
        }
        .sheet(isPresented: $showingLibrary, onDismiss: {
            libraryDismissed = true
            deliverSelection()
        }) {
            NanaLibraryMediaPicker(kind: kind, onLoading: { progress in
                importProgress = progress
                importing = true
                showingLibrary = false
            }) { result in
                importing = false
                importProgress = nil
                accept(result)
                showingLibrary = false
                if libraryDismissed { deliverSelection() }
            }.interactiveDismissDisabled()
        }
        .onDisappear {
            // Opening the full-screen camera also hides this sheet; it must not cancel that capture.
            if capture == nil && !showingLibrary {
                active = false
                permissionTask?.cancel()
                importProgress?.cancel()
                pending?.discard()
                pending = nil
            }
        }
        .onAppear { active = true }
    }

    private func choice(_ title: String, subtitle: String, asset: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                NanaAssetImage(assetKey: asset, contentMode: .fit).frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer(minLength: 0)
                NanaAssetImage(assetKey: "nana.voice.voice_asset_033", contentMode: .fit).frame(width: 12, height: 18)
            }
            .padding(.horizontal, 14).frame(minHeight: 68)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func openCamera(_ source: NanaCaptureKind) {
        error = nil
        needsSettings = false
        let type = source == .video ? UTType.movie.identifier : UTType.image.identifier
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              UIImagePickerController.availableMediaTypes(for: .camera)?.contains(type) == true else {
            error = "This camera isn't available. You can choose from your library instead."
            return
        }
        requestingPermission = true
        permissionTask = Task { @MainActor in
            let missing = await NanaMediaPermissions.request(video: true, audio: source == .video)
            guard !Task.isCancelled, active else { return }
            requestingPermission = false
            if missing.isEmpty { capture = source }
            else {
                error = "Allow \(missing.joined(separator: " and ").lowercased()) access in Settings to continue."
                needsSettings = true
            }
        }
    }

    private func accept(_ result: NanaMediaPickResult) {
        switch result {
        case .selected(let media):
            guard active else { media.discard(); return }
            pending?.discard(); pending = media
        case .failed(let message): error = message; needsSettings = false
        case .cancelled: break
        }
    }

    private func deliverSelection() {
        guard let media = pending else { return }
        pending = nil
        onSelect(media)
        dismiss()
    }
}

private enum NanaMediaImport {
    static func photo(_ data: Data) -> NanaMediaPickResult {
        guard data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else {
            return .failed("Choose a readable photo smaller than 25 MB.")
        }
        return .selected(NanaPickedMedia(content: .photo(jpeg)))
    }

    static func video(_ original: URL) -> NanaMediaPickResult {
        do {
            let size = try original.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 250_000_000 else { return .failed("Choose a video smaller than 250 MB.") }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NanaMediaAttachments", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(original.pathExtension.isEmpty ? "mov" : original.pathExtension)
            try FileManager.default.copyItem(at: original, to: copy)
            return .selected(NanaPickedMedia(content: .video(copy)))
        } catch { return .failed("Couldn't load this video. Please try another one.") }
    }
}

private struct NanaCameraMediaPicker: UIViewControllerRepresentable {
    let kind: NanaCaptureKind
    let onResult: (NanaMediaPickResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [kind == .video ? UTType.movie.identifier : UTType.image.identifier]
        picker.cameraCaptureMode = kind == .video ? .video : .photo
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 60
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (NanaMediaPickResult) -> Void
        init(onResult: @escaping (NanaMediaPickResult) -> Void) { self.onResult = onResult }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onResult(.cancelled) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                onResult(NanaMediaImport.video(url))
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                onResult(NanaMediaImport.photo(data))
            } else { onResult(.failed("Couldn't use this capture. Please try again.")) }
        }
    }
}

private struct NanaLibraryMediaPicker: UIViewControllerRepresentable {
    let kind: NanaMediaSourceKind
    let onLoading: (Progress) -> Void
    let onResult: (NanaMediaPickResult) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onLoading: onLoading, onResult: onResult) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = kind == .photos ? .images : .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onResult: (NanaMediaPickResult) -> Void
        private var loading = false
        let onLoading: (Progress) -> Void
        init(onLoading: @escaping (Progress) -> Void, onResult: @escaping (NanaMediaPickResult) -> Void) {
            self.onLoading = onLoading
            self.onResult = onResult
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !loading else { return }
            guard let provider = results.first?.itemProvider else { onResult(.cancelled); return }
            loading = true
            picker.view.isUserInteractionEnabled = false
            let video = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            let progress = provider.loadFileRepresentation(forTypeIdentifier: video ? UTType.movie.identifier : UTType.image.identifier) { url, _ in
                let result: NanaMediaPickResult
                if let url {
                    if video { result = NanaMediaImport.video(url) }
                    else if let data = try? Data(contentsOf: url, options: .mappedIfSafe) { result = NanaMediaImport.photo(data) }
                    else { result = .failed("Couldn't load this photo. Please try another one.") }
                } else { result = .failed("Couldn't download this item. Check your connection and try again.") }
                DispatchQueue.main.async { self.onResult(result) }
            }
            onLoading(progress)
        }
    }
}
