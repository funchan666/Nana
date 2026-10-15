import Foundation
import UIKit
import AVFoundation

enum NanaRemoteMedia {
    enum Kind: String, Codable, Sendable { case image, video }

    struct Entry: Codable, Sendable {
        let assetKey: String
        let kind: Kind
        let url: URL
    }

    static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "NanaRemoteMedia", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.filter { $0.url.scheme == "https" && $0.url.host != nil }
    }()
    private static let byKey = Dictionary(entries.map { ($0.assetKey, $0) }, uniquingKeysWith: { first, _ in first })

    static func source(for key: String) -> Entry? {
        if let entry = byKey[key] { return entry }
        guard let url = URL(string: key), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        let kind: Kind = ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased()) ? .video : .image
        return Entry(assetKey: key, kind: kind, url: url)
    }
}

@MainActor
final class NanaRemoteImageStore {
    static let shared = NanaRemoteImageStore()

    private struct Job {
        let id: UUID
        let task: Task<UIImage?, Never>
        var readers: Set<UUID>
    }

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var jobs: [String: Job] = [:]
    private var activeThumbnails = 0
    private var thumbnailWaiters: [(UUID, CheckedContinuation<Bool, Never>)] = []

    private init() {
        cache.totalCostLimit = 40 * 1024 * 1024
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        session = URLSession(configuration: configuration)
    }

    func clear() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
        let tasks = jobs.values.map(\.task)
        jobs.removeAll()
        tasks.forEach { $0.cancel() }
    }

    func image(for source: NanaRemoteMedia.Entry) async -> UIImage? {
        let key = source.kind.rawValue + ":" + source.url.absoluteString
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let reader = UUID()
        let task: Task<UIImage?, Never>
        let jobID: UUID
        if let job = jobs[key] {
            task = job.task
            jobID = job.id
            jobs[key]?.readers.insert(reader)
        } else {
            jobID = UUID()
            task = Task { [weak self] in await self?.load(source) }
            jobs[key] = Job(id: jobID, task: task, readers: [reader])
        }
        return await withTaskCancellationHandler {
            defer { release(reader, key: key, jobID: jobID) }
            guard !Task.isCancelled else { return nil }
            let image = await task.value
            guard !Task.isCancelled, jobs[key]?.id == jobID else { return nil }
            if let image {
                let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                cache.setObject(image, forKey: key as NSString, cost: cost)
            }
            return image
        } onCancel: {
            Task { @MainActor [weak self] in self?.release(reader, key: key, jobID: jobID) }
        }
    }

    private func release(_ reader: UUID, key: String, jobID: UUID) {
        guard jobs[key]?.id == jobID else { return }
        jobs[key]?.readers.remove(reader)
        if jobs[key]?.readers.isEmpty == true { jobs.removeValue(forKey: key)?.task.cancel() }
    }

    private func load(_ source: NanaRemoteMedia.Entry) async -> UIImage? {
        do {
            try Task.checkCancellation()
            if source.kind == .video { return await thumbnail(for: source.url) }
            let (data, response) = try await session.data(from: source.url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  data.count <= 20 * 1024 * 1024, !Task.isCancelled,
                  let image = UIImage(data: data) else { return nil }
            let prepared = await image.byPreparingThumbnail(ofSize: CGSize(width: 1_600, height: 1_600))
            return Task.isCancelled ? nil : prepared
        } catch { return nil }
    }

    private func acquireThumbnailSlot() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else if activeThumbnails < 2 {
                    activeThumbnails += 1
                    continuation.resume(returning: true)
                } else { thumbnailWaiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let index = self.thumbnailWaiters.firstIndex(where: { $0.0 == id }) else { return }
                self.thumbnailWaiters.remove(at: index).1.resume(returning: false)
            }
        }
    }

    private func releaseThumbnailSlot() {
        if thumbnailWaiters.isEmpty { activeThumbnails -= 1 }
        else { thumbnailWaiters.removeFirst().1.resume(returning: true) }
    }

    private func thumbnail(for url: URL) async -> UIImage? {
        guard await acquireThumbnailSlot() else { return nil }
        defer { releaseThumbnailSlot() }
        guard !Task.isCancelled else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            generator.cancelAllCGImageGeneration()
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            do {
                let result = try await generator.image(at: .zero)
                guard !Task.isCancelled else { return nil }
                return UIImage(cgImage: result.image)
            } catch { return nil }
        } onCancel: {
            Task { @MainActor in generator.cancelAllCGImageGeneration() }
        }
    }
}
