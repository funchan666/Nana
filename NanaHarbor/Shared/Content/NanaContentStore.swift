import Foundation
import Combine
import CryptoKit

enum NanaDevelopmentMode {
    static var usesFixtures: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-NanaDevelopmentFixtures")
        #else
        false
        #endif
    }
}

enum NanaReadState: Equatable {
    case idle, loading
    case loaded(Date)
    case failed(NanaAServiceError)
}

@MainActor
final class NanaContentStore: ObservableObject {
    @Published private(set) var payload: NanaContentSnapshot = .empty
    @Published private(set) var states: [NanaReadEndpoint: NanaReadState] = [:]
    @Published private(set) var blockedProfileIDs: Set<String> = []
    @Published private(set) var accountScope: String?
    @Published var selectedCategory = "For you"
    @Published var searchFilter = NanaSearchFilter()
    @Published var actionNotice: AccountEntryNotice?
    @Published private(set) var assetManifest: [NanaAssetDescriptor] = []

    private let service: NanaAServiceClient
    private var fetchedAt: [NanaReadEndpoint: Date] = [:]
    private var requests: [NanaReadEndpoint: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var drafts: [String: String] = [:]
    private var cacheURL: URL?
    private(set) var cacheSaveFailed = false

    init(service: NanaAServiceClient = NanaAServiceClient()) { self.service = service }

    var categories: [String] { ["For you", "Following", "Late night", "Creative", "Music", "Open talk"] }
    var checkedInToday: Bool { false }
    var visibleConversations: [NanaConversation] { payload.conversations.filter { !blockedProfileIDs.contains($0.profileID) } }

    func beginSession(accountID: String?) {
        guard accountScope != accountID else { return }
        let oldURL = cacheURL
        generation = UUID()
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        payload = .empty
        states = [:]
        fetchedAt = [:]
        blockedProfileIDs = []
        drafts = [:]
        assetManifest = []
        actionNotice = nil
        cacheSaveFailed = false
        accountScope = accountID
        cacheURL = nil
        // Private snapshots and local overlays never cross accounts or survive logout.
        if let oldURL { try? FileManager.default.removeItem(at: oldURL) }
        guard let accountID else { return }
        if NanaDevelopmentMode.usesFixtures {
            #if DEBUG
            payload = .sample
            #endif
        }
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        if let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            cacheURL = directory.appendingPathComponent("NanaReadCache", isDirectory: true).appendingPathComponent(digest + ".json")
        }
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(NanaReadCache.self, from: data),
              cache.version == 1 else { return }
        payload = cache.snapshot
        fetchedAt = cache.fetchedAt
        blockedProfileIDs = cache.hiddenProfiles
        drafts = cache.drafts
        assetManifest = cache.assets
    }

    func state(for endpoint: NanaReadEndpoint) -> NanaReadState { states[endpoint] ?? .idle }
    func hasContent(for endpoint: NanaReadEndpoint) -> Bool {
        fetchedAt[endpoint] != nil || (endpoint != .assetManifest && fetchedAt[.bootstrap] != nil) || NanaDevelopmentMode.usesFixtures
    }

    /// Revalidate on screen entry or explicit refresh. No TTL is invented for the fixed JSON contract.
    func refresh(_ endpoint: NanaReadEndpoint) async {
        guard accountScope != nil else { return }
        if let running = requests[endpoint] { await running.value; return }
        let requestGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return }
            self.states[endpoint] = .loading
            do {
                let update = try await self.fetch(endpoint)
                try Task.checkCancellation()
                guard self.generation == requestGeneration else { return }
                update()
                self.fetchedAt[endpoint] = Date()
                self.states[endpoint] = .loaded(Date())
                self.persist()
            } catch {
                guard self.generation == requestGeneration else { return }
                if Task.isCancelled || error is CancellationError {
                    self.states[endpoint] = self.fetchedAt[endpoint].map(NanaReadState.loaded) ?? .idle
                } else {
                    let failure = NanaAServiceClient.sanitize(error)
                    self.states[endpoint] = .failed(failure)
                    // A content-service 401 cannot expire a local membership or
                    // an Apple credential. Preserve the snapshot and allow retry.
                }
            }
            if self.generation == requestGeneration { self.requests[endpoint] = nil }
        }
        requests[endpoint] = task
        await task.value
    }

    /// Decode completely before replacing any visible data, and apply only the endpoint's slice.
    private func fetch(_ endpoint: NanaReadEndpoint) async throws -> () -> Void {
        switch endpoint {
        case .bootstrap:
            let value = try await service.read(endpoint, as: NanaContentSnapshot.self)
            return { self.payload = value }
        case .homeFeed:
            let value = try await service.read(endpoint, as: NanaHomeFeedPayload.self)
            return { self.payload.rooms = value.rooms; self.payload.posts = value.posts }
        case .rooms:
            let value = try await service.read(endpoint, as: NanaRoomsPayload.self)
            return { self.payload.rooms = value.rooms }
        case .auroraRoom:
            let value = try await service.read(endpoint, as: NanaRoomDetailPayload.self)
            guard value.room.id == "room-aurora", value.seats.allSatisfy({ $0.roomID == value.room.id }),
                  value.messages.allSatisfy({ $0.roomID == value.room.id }) else { throw NanaAServiceError.invalidResponse }
            return {
                self.upsert(value.room, into: &self.payload.rooms)
                self.payload.roomSeats.removeAll { $0.roomID == value.room.id }
                self.payload.roomSeats += value.seats
                self.payload.roomMessages.removeAll { $0.roomID == value.room.id }
                self.payload.roomMessages += value.messages
                self.payload.gifts = value.gifts
            }
        case .avaProfile:
            let value = try await service.read(endpoint, as: NanaProfilePayload.self)
            guard value.profile.id == "profile-ava" else { throw NanaAServiceError.invalidResponse }
            return { self.upsert(value.profile, into: &self.payload.profiles) }
        case .echoesPost:
            let value = try await service.read(endpoint, as: NanaPostPayload.self)
            guard value.post.id == "post-echoes" else { throw NanaAServiceError.invalidResponse }
            return { self.upsert(value.post, into: &self.payload.posts) }
        case .search:
            let value = try await service.read(endpoint, as: NanaSearchPayload.self)
            return { self.payload.profiles = value.profiles; self.payload.rooms = value.rooms; self.payload.posts = value.posts }
        case .conversations:
            let value = try await service.read(endpoint, as: NanaConversationsPayload.self)
            return { self.payload.conversations = value.conversations }
        case .avaMessages:
            let value = try await service.read(endpoint, as: NanaMessagesPayload.self)
            guard value.messages.allSatisfy({ $0.conversationID == "conversation-ava" }) else { throw NanaAServiceError.invalidResponse }
            return { self.payload.messages.removeAll { $0.conversationID == "conversation-ava" }; self.payload.messages += value.messages }
        case .wallet:
            let value = try await service.read(endpoint, as: NanaWalletPayload.self)
            guard value.wallet.coinBalance >= 0, value.wallet.nextLevelPoints > 0 else { throw NanaAServiceError.invalidResponse }
            return { self.payload.wallet = value.wallet }
        case .gifts:
            let value = try await service.read(endpoint, as: NanaGiftsPayload.self)
            guard value.gifts.allSatisfy({ $0.coinCost >= 0 }) else { throw NanaAServiceError.invalidResponse }
            return { self.payload.gifts = value.gifts }
        case .assetManifest:
            let value = try await service.read(endpoint, as: NanaAssetManifestPayload.self)
            return { self.assetManifest = value.assets }
        }
    }

    private func upsert<Item: Identifiable>(_ item: Item, into items: inout [Item]) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
    }

    func room(with id: String) -> NanaLiveRoom? { payload.rooms.first { $0.id == id && !blockedProfileIDs.contains($0.hostID) } }
    func profile(with id: String) -> NanaProfile? { payload.profiles.first { $0.id == id && !blockedProfileIDs.contains($0.id) } }
    func post(with id: String) -> NanaPost? { payload.posts.first { $0.id == id && !blockedProfileIDs.contains($0.authorID) } }
    func posts(for filter: NanaSearchFilter? = nil) -> [NanaPost] {
        if let filter, filter.kind == .people || filter.kind == .rooms { return [] }
        return payload.posts.filter { !blockedProfileIDs.contains($0.authorID) }
    }
    func filteredProfiles(for filter: NanaSearchFilter) -> [NanaProfile] {
        payload.profiles.filter { profile in
            !blockedProfileIDs.contains(profile.id) && profile.age >= filter.minimumAge && profile.age <= filter.maximumAge &&
            (filter.region == "All regions" || profile.region == filter.region) &&
            (filter.language == "All languages" || profile.language == filter.language) &&
            (filter.gender == "Any" || profile.gender == filter.gender)
        }
    }
    func filteredRooms(for filter: NanaSearchFilter) -> [NanaLiveRoom] {
        guard filter.kind != .people && filter.kind != .posts else { return [] }
        let filteringPeople = filter.minimumAge != 18 || filter.maximumAge != 45 || filter.region != "All regions" || filter.language != "All languages" || filter.gender != "Any"
        let hosts = Set(filteredProfiles(for: filter).map(\.id))
        return payload.rooms.filter { !blockedProfileIDs.contains($0.hostID) && (!filteringPeople || hosts.contains($0.hostID)) }
    }

    func explainUnavailable(_ action: String) {
        actionNotice = AccountEntryNotice(title: "\(action) isn't available yet", explanation: NanaAServiceError.writeUnavailable.localizedDescription)
    }
    func dismissActionNotice() { actionNotice = nil }
    func toggleConnection(for profileID: String) { explainUnavailable("Following") }
    func appendMessage(to conversationID: String, body: String) { explainUnavailable("Sending messages") }
    func appendRoomMessage(roomID: String, body: String, senderName: String = "You") { explainUnavailable("Room chat") }
    func toggleMute(roomID: String, seatID: String) { explainUnavailable("Room moderation") }
    func kick(roomID: String, seatID: String) { explainUnavailable("Room moderation") }
    func performCheckIn() { explainUnavailable("Check-in") }
    func sendGift(_ gift: NanaGift, to roomID: String) { explainUnavailable("Sending gifts") }

    /// A device-only safety preference; never described as a submitted report/server block.
    func block(profileID: String) {
        blockedProfileIDs.insert(profileID)
        persist()
        actionNotice = AccountEntryNotice(title: "Profile hidden", explanation: "This profile and its rooms, posts and conversations are hidden from your view.")
    }
    func draft(for key: String) -> String { drafts[key] ?? "" }
    func saveDraft(_ value: String, for key: String) { drafts[key] = value; persist() }

    private func persist() {
        guard let cacheURL, !NanaDevelopmentMode.usesFixtures else { return }
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var directoryURL = directory
            try directoryURL.setResourceValues(resourceValues)
            let cache = NanaReadCache(version: 1, snapshot: payload, fetchedAt: fetchedAt, hiddenProfiles: blockedProfileIDs, drafts: drafts, assets: assetManifest)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            cacheSaveFailed = false
        } catch { cacheSaveFailed = true }
    }
}

private struct NanaReadCache: Codable {
    let version: Int
    let snapshot: NanaContentSnapshot
    let fetchedAt: [NanaReadEndpoint: Date]
    let hiddenProfiles: Set<String>
    let drafts: [String: String]
    let assets: [NanaAssetDescriptor]
}
