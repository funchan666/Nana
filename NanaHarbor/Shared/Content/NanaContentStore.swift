import Foundation
import Combine
import CryptoKit
import UIKit
import ImageIO

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
    @Published private(set) var accountInbox: NanaAccountInboxSnapshot?
    @Published var selectedCategory = "For you"
    @Published var searchFilter = NanaSearchFilter()
    @Published var actionNotice: AccountEntryNotice?
    @Published private(set) var assetManifest: [NanaAssetDescriptor] = []

    @Published private(set) var personal = NanaPersonalState()
    @Published private(set) var safetyDismissalID = UUID()
    private var personalURL: URL?
    private var personalStorageReady = false

    private let service: NanaAServiceClient
    private var fetchedAt: [NanaReadEndpoint: Date] = [:]
    private var requests: [NanaReadEndpoint: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var drafts: [String: String] = [:]
    private var cacheURL: URL?
    private(set) var cacheSaveFailed = false

    init(service: NanaAServiceClient = NanaAServiceClient()) { self.service = service }

    var categories: [String] { ["For you", "Following", "Late night", "Creative", "Music", "Open talk"] }
    var checkedInToday: Bool { personal.checkInDays.contains(dayKey(Date())) }
    var activityPoints: Int { personal.checkInDays.count * 10 }
    var activityLevel: Int { 1 + activityPoints / 200 }
    var followedProfiles: [NanaProfile] {
        personal.followedProfiles.values.filter { !hiddenAuthorIDs.contains($0.id) }.sorted { $0.displayName < $1.displayName }
    }
    var hiddenProfiles: [NanaProfile] { personal.hiddenProfiles.values.sorted { $0.displayName < $1.displayName } }
    var hiddenAuthorIDs: Set<String> {
        var ids = blockedProfileIDs.union(personal.reportedProfileIDs ?? [])
        for id in Array(ids) { ids.formUnion(personal.safetyAuthorAliases?[id] ?? []) }
        return relatedAuthorIDs(ids)
    }
    var visibleProfiles: [NanaProfile] { payload.profiles.filter { !hiddenAuthorIDs.contains($0.id) } }
    var hiddenPortraitAssetKeys: Set<String> {
        let hiddenIDs = hiddenAuthorIDs
        var photos = Set(payload.profiles.filter { hiddenIDs.contains($0.id) }.compactMap(\.avatarAssetKey))
        photos.formUnion(payload.rooms.filter { hiddenIDs.contains($0.hostID) }.compactMap(\.hostAvatarAssetKey))
        for id in blockedProfileIDs.union(personal.reportedProfileIDs ?? []) {
            photos.formUnion(personal.safetyPortraits?[id] ?? [])
            if let photo = personal.hiddenProfiles[id]?.avatarAssetKey { photos.insert(photo) }
        }
        return photos
    }

    private func safetyPortraits(for context: NanaPostDiscussion) -> Set<String> {
        let ids = relatedAuthorIDs([context.authorID])
        var photos = Set(payload.profiles.filter { ids.contains($0.id) }.compactMap(\.avatarAssetKey))
        photos.formUnion(payload.rooms.filter { ids.contains($0.hostID) }.compactMap(\.hostAvatarAssetKey))
        if let photo = context.authorAvatar { photos.insert(photo) }
        return photos
    }

    private func relatedAuthorIDs(_ initial: Set<String>) -> Set<String> {
        var ids = initial
        var pairs: [(String, String)] = payload.rooms.compactMap { room in
            guard let asset = room.streamAssetKey, asset.hasPrefix("nana.video.") else { return nil }
            return (room.hostID, videoCreatorID(NanaBundledVideo(assetKey: asset)))
        }
        pairs += payload.posts.compactMap { post in
            guard let asset = post.coverAssetKey, asset.hasPrefix("nana.video.") else { return nil }
            return (post.authorID, videoCreatorID(NanaBundledVideo(assetKey: asset)))
        }
        var previousCount = -1
        while previousCount != ids.count {
            previousCount = ids.count
            for (profileID, creatorID) in pairs where ids.contains(profileID) || ids.contains(creatorID) {
                ids.insert(profileID); ids.insert(creatorID)
            }
        }
        return ids
    }

    func isRoomVisible(_ room: NanaLiveRoom) -> Bool {
        guard !hiddenAuthorIDs.contains(room.hostID), !(personal.hiddenRoomIDs ?? []).contains(room.id) else { return false }
        guard let asset = room.streamAssetKey else { return true }
        return !(personal.hiddenPostKeys ?? []).contains(asset)
    }

    func roomMessages(for roomID: String) -> [NanaRoomChatMessage] {
        let hiddenNames = Set((payload.profiles + Array(personal.hiddenProfiles.values))
            .filter { hiddenAuthorIDs.contains($0.id) }.flatMap {
                [$0.displayName.lowercased(), $0.displayName.components(separatedBy: " ").first?.lowercased() ?? "", $0.handle.lowercased()]
            })
        // Legacy room messages carry only a sender name, so filter those conservatively.
        return payload.roomMessages.filter { message in
            guard message.roomID == roomID else { return false }
            if let id = message.senderID { return !hiddenAuthorIDs.contains(id) }
            return !hiddenNames.contains(message.senderName.lowercased())
        }
    }
    var visibleConversations: [NanaConversation] {
        guard let accountInbox, accountInbox.accountID == accountScope else { return [] }
        return accountInbox.conversations.filter { !hiddenAuthorIDs.contains($0.profileID) && !personal.hiddenConversationIDs.contains($0.id) }.map {
            var conversation = $0
            if personal.readConversations[$0.id] == conversationRevision($0) { conversation.unreadCount = 0 }
            return conversation
        }
    }

    var liveFriendRooms: [NanaLiveRoom] {
        guard let accountInbox, accountInbox.accountID == accountScope else { return [] }
        let friends = Set(accountInbox.mutualFriends.filter {
            !hiddenAuthorIDs.contains($0.id) && personal.following[$0.id] != false
        }.map(\.id))
        var shownHosts = Set<String>()
        return accountInbox.liveRooms.filter { room in
            friends.contains(room.hostID) && isRoomVisible(room)
                && room.streamSourceType != "simulatedReplay"
                && room.streamAssetKey?.hasPrefix("nana.video.") != true
                && ["live", "live now"].contains(room.roomState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                && shownHosts.insert(room.hostID).inserted
        }
    }

    var mutualFriends: [NanaProfile] {
        guard let accountInbox, accountInbox.accountID == accountScope else { return [] }
        return accountInbox.mutualFriends.filter {
            !hiddenAuthorIDs.contains($0.id) && personal.following[$0.id] != false
        }.map {
            var profile = $0
            profile.isConnected = true
            return profile
        }
    }

    var newFollowers: [NanaProfile] {
        guard let accountInbox, accountInbox.accountID == accountScope else { return [] }
        return accountInbox.newFollowers.filter { !hiddenAuthorIDs.contains($0.id) }
    }

    var accountFollowers: [NanaProfile] {
        guard let accountInbox, accountInbox.accountID == accountScope else { return [] }
        var seen = Set<String>()
        return (accountInbox.followers + accountInbox.mutualFriends + accountInbox.newFollowers).filter {
            !hiddenAuthorIDs.contains($0.id) && seen.insert($0.id).inserted
        }
    }

    func conversationMessages(for conversationID: String) -> [NanaMessage] {
        guard let accountInbox, accountInbox.accountID == accountScope,
              visibleConversations.contains(where: { $0.id == conversationID }) else { return [] }
        return accountInbox.messages.filter {
            $0.conversationID == conversationID && !hiddenAuthorIDs.contains($0.senderID)
        }
    }

    /// Integration boundary for a future authenticated messaging service. The
    /// current anonymous read-only export must never populate a private inbox.
    func replaceAccountInbox(_ snapshot: NanaAccountInboxSnapshot) {
        guard snapshot.accountID == accountScope else { return }
        accountInbox = snapshot
    }

    func beginSession(accountID: String?) {
        guard accountScope != accountID else { return }
        let oldURL = cacheURL
        generation = UUID()
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        payload = .empty
        accountInbox = nil
        states = [:]
        fetchedAt = [:]
        blockedProfileIDs = []
        drafts = [:]
        personal = NanaPersonalState()
        personalURL = nil
        personalStorageReady = false
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
            applyReplayCatalog()
            #endif
        }
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        if let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            cacheURL = directory.appendingPathComponent("NanaReadCache", isDirectory: true).appendingPathComponent(digest + ".json")
            personalURL = directory.appendingPathComponent("NanaPersonalData", isDirectory: true).appendingPathComponent(digest, isDirectory: true).appendingPathComponent("personal.json")
        }
        let shouldMigrateLegacySafety = personalURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
        if let personalURL {
            do {
                if FileManager.default.fileExists(atPath: personalURL.path) {
                    personal = try JSONDecoder().decode(NanaPersonalState.self, from: Data(contentsOf: personalURL))
                }
                personalStorageReady = true
                blockedProfileIDs = Set(personal.hiddenProfiles.keys)
                drafts = personal.drafts
            } catch {
                actionNotice = AccountEntryNotice(title: "Saved data unavailable", explanation: "Please reopen Nana to try again. Your saved data has not been replaced.")
            }
        }
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(NanaReadCache.self, from: data),
              cache.version == 1 else { return }
        payload = cache.snapshot
        fetchedAt = cache.fetchedAt
        if shouldMigrateLegacySafety { blockedProfileIDs.formUnion(cache.hiddenProfiles) }
        if personalStorageReady {
            var migrated = personal
            for id in cache.hiddenProfiles where shouldMigrateLegacySafety {
                if let profile = cache.snapshot.profiles.first(where: { $0.id == id }) { migrated.hiddenProfiles[id] = profile }
            }
            migrated.drafts.merge(cache.drafts, uniquingKeysWith: { current, _ in current })
            _ = savePersonal(migrated)
        }
        drafts = personal.drafts
        applyPersonalOverlays()
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
                self.applyPersonalOverlays()
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

    func room(with id: String) -> NanaLiveRoom? { payload.rooms.first { $0.id == id && isRoomVisible($0) } }
    func profile(with id: String) -> NanaProfile? {
        guard !hiddenAuthorIDs.contains(id) else { return nil }
        guard var profile = (mutualFriends + newFollowers + visibleProfiles).first(where: { $0.id == id }) else { return nil }
        if let following = personal.following[id] { profile.isConnected = following }
        return profile
    }
    func post(with id: String) -> NanaPost? { posts().first { $0.id == id } }
    func posts(for filter: NanaSearchFilter? = nil) -> [NanaPost] {
        if let filter, filter.kind == .people || filter.kind == .rooms { return [] }
        return payload.posts.filter { post in
            guard !hiddenAuthorIDs.contains(post.authorID), !(personal.hiddenPostKeys ?? []).contains(post.id) else { return false }
            if let asset = post.coverAssetKey, asset.hasPrefix("nana.video.") {
                return isVideoVisible(NanaBundledVideo(assetKey: asset))
            }
            return true
        }
    }
    func filteredProfiles(for filter: NanaSearchFilter) -> [NanaProfile] {
        payload.profiles.filter { profile in
            !hiddenAuthorIDs.contains(profile.id) && profile.age >= filter.minimumAge && profile.age <= filter.maximumAge &&
            (filter.region == "All regions" || profile.region == filter.region) &&
            (filter.language == "All languages" || profile.language == filter.language) &&
            (filter.gender == "Any" || profile.gender == filter.gender)
        }
    }
    func filteredRooms(for filter: NanaSearchFilter) -> [NanaLiveRoom] {
        guard filter.kind != .people && filter.kind != .posts else { return [] }
        let filteringPeople = filter.minimumAge != 18 || filter.maximumAge != 45 || filter.region != "All regions" || filter.language != "All languages" || filter.gender != "Any"
        let hosts = Set(filteredProfiles(for: filter).map(\.id))
        return payload.rooms.filter { isRoomVisible($0) && (!filteringPeople || hosts.contains($0.hostID)) }
    }

    func replayAudience(for room: NanaLiveRoom) -> [NanaReplayAudienceMember] {
        guard room.streamSourceType == "simulatedReplay" else { return [] }
        let reservedPhotos = Set(payload.profiles.compactMap(\.avatarAssetKey) + payload.rooms.compactMap(\.hostAvatarAssetKey))
        let allocatedPhotos = NanaRoomPortraitAllocator.photosByRoom(
            rooms: payload.rooms, profiles: payload.profiles, seats: payload.roomSeats,
            blockedProfileIDs: [], excludedPhotoKeys: []
        )[room.id] ?? []
        let photos = allocatedPhotos.filter { !reservedPhotos.contains($0) }
        let names: [String]
        switch room.id {
        case "room-aurora": names = ["Maya", "Theo", "Iris", "Jude", "Hazel", "Eli", "Rose", "Felix"]
        case "room-studio": names = ["Ruby", "Finn", "Cleo", "Owen", "Poppy", "Levi", "Nina", "Hugo"]
        case "room-lantern": names = ["Aria", "Ezra", "Nell", "Kai", "Vera", "Dean", "Tess", "Leon"]
        case "room-midnight": names = ["Skye", "Luca", "Zoe", "Milo", "Luna", "Remy", "Wren", "Seth"]
        case "room-city": names = ["Ada", "Miles", "June", "Oscar", "Lucy", "Jasper", "Eva", "Cole"]
        case "room-outdoors": names = ["Freya", "Arlo", "Isla", "Ben", "Daisy", "Max", "Mae", "Rhys"]
        default: names = ["Alex", "Sam", "Charlie", "Robin", "Rowan", "Jamie", "Casey", "Taylor"]
        }
        let hiddenIDs = hiddenAuthorIDs
        let hiddenPhotos = hiddenPortraitAssetKeys
        return zip(names, photos).map { name, asset in
            NanaReplayAudienceMember(id: "\(room.id)-\(asset)", displayName: name, avatarAssetKey: asset)
        }.filter { !hiddenIDs.contains($0.id) && !hiddenPhotos.contains($0.avatarAssetKey) }
    }

    /// Local replay seats reuse the room's stable audience, without changing a
    /// published seat response or claiming a microphone transport is connected.
    func voiceRoomSeats(for room: NanaLiveRoom) -> [NanaRoomSeat] {
        let capacity = min(12, max(1, room.seatCapacity))
        let published = payload.roomSeats.filter { $0.roomID == room.id }
        let hiddenIDs = hiddenAuthorIDs
        var seats = (0..<capacity).map { position in
            if let seat = published.first(where: { $0.position == position }),
               seat.profileID.map({ !hiddenIDs.contains($0) }) ?? true { return seat }
            let hostFallback = position == 0 && published.isEmpty && !hiddenIDs.contains(room.hostID)
            return NanaRoomSeat(id: "\(room.id)-seat-\(position)", roomID: room.id, position: position,
                                profileID: hostFallback ? room.hostID : nil,
                                displayName: hostFallback ? room.hostName : nil,
                                role: hostFallback ? "Host" : "Listener", isMuted: false, isInvited: false)
        }
        guard room.streamSourceType == "simulatedReplay" else { return seats }
        let occupied = Set(seats.compactMap(\.profileID))
        var members = replayAudience(for: room).filter { !occupied.contains($0.id) }.makeIterator()
        // Keep a joinable seat in larger rooms. Small three-seat rooms use both
        // guest positions so the second row is not an empty stage.
        for index in seats.indices where index > 0 && seats[index].profileID == nil {
            if capacity >= 6 && index == capacity - 1 { continue }
            guard let member = members.next() else { break }
            seats[index] = NanaRoomSeat(id: seats[index].id, roomID: room.id, position: index,
                                       profileID: member.id, displayName: member.displayName,
                                       role: "Speaker", isMuted: index.isMultiple(of: 3), isInvited: false)
        }
        return seats
    }

    func displayedViewerCount(for room: NanaLiveRoom) -> Int {
        // A replay count must match its complete sample roster, not the four-image
        // header preview or an unrelated viewer total from the feed fixture.
        guard room.streamSourceType == "simulatedReplay" else { return room.viewerCount }
        let publishedIDs = payload.roomSeats.filter { $0.roomID == room.id }.compactMap(\.profileID)
            .filter { $0 != room.hostID && !hiddenAuthorIDs.contains($0) }
        return Set(replayAudience(for: room).map(\.id) + publishedIDs).count
    }

    func explainUnavailable(_ action: String) {
        actionNotice = AccountEntryNotice(title: "\(action) isn't available yet", explanation: NanaAServiceError.writeUnavailable.localizedDescription)
    }
    func dismissActionNotice() { actionNotice = nil }
    func completeSafetyAction() { safetyDismissalID = UUID() }
    func toggleConnection(for profileID: String) {
        guard var profile = self.profile(with: profileID) ?? personal.followedProfiles[profileID] else { return }
        var updated = personal
        let following = !(personal.following[profileID] ?? profile.isConnected)
        updated.following[profileID] = following
        profile.isConnected = following
        if following { updated.followedProfiles[profileID] = profile } else { updated.followedProfiles.removeValue(forKey: profileID) }
        if savePersonal(updated) { applyPersonalOverlays() }
    }
    func appendMessage(to conversationID: String, body: String) { explainUnavailable("Sending messages") }
    func appendRoomMessage(roomID: String, body: String, senderName: String = "You") { explainUnavailable("Room chat") }
    func toggleMute(roomID: String, seatID: String) { explainUnavailable("Room moderation") }
    func kick(roomID: String, seatID: String) { explainUnavailable("Room moderation") }
    func performCheckIn() {
        guard !checkedInToday else { return }
        var updated = personal
        updated.checkInDays.insert(dayKey(Date()))
        if savePersonal(updated) {
            actionNotice = AccountEntryNotice(title: "Checked in", explanation: "+10 activity points. See you tomorrow.")
        }
    }

    @discardableResult
    func block(profileID: String) -> Bool {
        guard let profile = self.profile(with: profileID) ?? personal.followedProfiles[profileID] else { return false }
        return blockPostAuthor(discussion(for: profile))
    }
    func draft(for key: String) -> String { drafts[key] ?? "" }

    func discussion(for post: NanaPost) -> NanaPostDiscussion {
        NanaPostDiscussion(key: post.id, title: post.title, authorID: post.authorID,
                           authorName: post.authorName, authorAvatar: profile(with: post.authorID)?.avatarAssetKey,
                           videoAssetKey: post.coverAssetKey?.hasPrefix("nana.video.") == true ? post.coverAssetKey : nil)
    }

    func discussion(for profile: NanaProfile) -> NanaPostDiscussion {
        NanaPostDiscussion(key: profile.id, title: profile.displayName, authorID: profile.id,
                           authorName: profile.displayName, authorAvatar: profile.avatarAssetKey, videoAssetKey: nil, kind: .profile)
    }

    func discussion(for room: NanaLiveRoom) -> NanaPostDiscussion {
        NanaPostDiscussion(key: room.id, title: room.title, authorID: room.hostID,
                           authorName: room.hostName, authorAvatar: room.hostAvatarAssetKey, videoAssetKey: room.streamAssetKey, kind: .room)
    }

    func discussion(for conversation: NanaConversation) -> NanaPostDiscussion {
        NanaPostDiscussion(key: conversation.id, title: conversation.displayName, authorID: conversation.profileID,
                           authorName: conversation.displayName, authorAvatar: conversation.avatarAssetKey, videoAssetKey: nil, kind: .conversation)
    }

    func discussion(for clip: NanaBundledVideo) -> NanaPostDiscussion {
        if let post = payload.posts.first(where: { $0.coverAssetKey == clip.assetKey }) { return discussion(for: post) }
        return NanaPostDiscussion(key: clip.id, title: clip.creatorLabel, authorID: videoCreatorID(clip),
                                  authorName: clip.creatorLabel, authorAvatar: nil, videoAssetKey: clip.assetKey)
    }

    private func videoCreatorID(_ clip: NanaBundledVideo) -> String { "video-creator-" + clip.creatorLabel.lowercased() }

    func isVideoVisible(_ clip: NanaBundledVideo) -> Bool {
        let context = discussion(for: clip)
        let hidden = personal.hiddenPostKeys ?? []
        return !hiddenAuthorIDs.contains(context.authorID) && !hiddenAuthorIDs.contains(videoCreatorID(clip))
            && !hidden.contains(context.key) && !hidden.contains(clip.id)
    }

    func comments(for context: NanaPostDiscussion) -> [NanaPostComment] {
        let samples = NanaPostCommentSamples.comments(for: context)
        return (samples + (personal.postComments?[context.key] ?? [])).filter { !hiddenAuthorIDs.contains($0.authorID) }
    }

    @discardableResult
    func addComment(_ body: String, to context: NanaPostDiscussion, senderName: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500 else { return false }
        var updated = personal
        var comments = updated.postComments ?? [:]
        comments[context.key, default: []].append(NanaPostComment(
            id: UUID().uuidString, authorID: "local-account", authorName: senderName,
            avatarAssetKey: nil, body: trimmed, timeLabel: Date().formatted(date: .abbreviated, time: .shortened)))
        updated.postComments = comments
        updated.drafts["post-comment-\(context.key)"] = ""
        guard savePersonal(updated) else { return false }
        drafts = updated.drafts
        return true
    }

    @discardableResult
    func reportContent(_ context: NanaPostDiscussion, reason: String) -> Bool {
        var updated = personal
        var reports = updated.safetyReports ?? []
        reports.removeAll { $0.contentKey == context.key && $0.kind == context.kind }
        reports.append(NanaSafetyReport(contentKey: context.key, kind: context.kind, authorID: context.authorID, reason: reason, createdAt: Date()))
        updated.safetyReports = reports
        switch context.kind {
        case .post: updated.hiddenPostKeys = (updated.hiddenPostKeys ?? []).union([context.key])
        case .room: updated.hiddenRoomIDs = (updated.hiddenRoomIDs ?? []).union([context.key])
        case .conversation: updated.hiddenConversationIDs.insert(context.key)
        case .profile:
            updated.reportedProfileIDs = (updated.reportedProfileIDs ?? []).union([context.authorID])
            var aliases = updated.safetyAuthorAliases ?? [:]
            aliases[context.authorID] = relatedAuthorIDs([context.authorID])
            updated.safetyAuthorAliases = aliases
            var portraits = updated.safetyPortraits ?? [:]
            portraits[context.authorID] = safetyPortraits(for: context)
            updated.safetyPortraits = portraits
        }
        if updated.hiddenPostKeys == nil { updated.hiddenPostKeys = [] }
        if let asset = context.videoAssetKey { updated.hiddenPostKeys?.insert(asset) }
        return savePersonal(updated)
    }

    @discardableResult
    func blockPostAuthor(_ context: NanaPostDiscussion) -> Bool {
        let author = payload.profiles.first { $0.id == context.authorID } ?? NanaProfile(
            id: context.authorID, displayName: context.authorName, handle: context.authorName,
            region: "", language: "", gender: "", age: 0, introduction: "", avatarAssetKey: context.authorAvatar,
            isConnected: false, followerCount: 0, followingCount: 0, level: 0)
        var updated = personal
        updated.hiddenProfiles[author.id] = author
        var aliases = updated.safetyAuthorAliases ?? [:]
        aliases[author.id] = relatedAuthorIDs([author.id])
        updated.safetyAuthorAliases = aliases
        var portraits = updated.safetyPortraits ?? [:]
        portraits[author.id] = safetyPortraits(for: context)
        updated.safetyPortraits = portraits
        guard savePersonal(updated) else { return false }
        blockedProfileIDs.insert(author.id)
        return true
    }
    @discardableResult
    func saveDraft(_ value: String, for key: String) -> Bool {
        var updated = personal
        updated.drafts[key] = value
        guard savePersonal(updated) else { return false }
        drafts = updated.drafts
        return true
    }

    func unhide(profileID: String) {
        var updated = personal
        updated.hiddenProfiles.removeValue(forKey: profileID)
        if savePersonal(updated) { blockedProfileIDs.remove(profileID) }
    }

    func preference(_ key: String, default fallback: Bool = true) -> Bool { personal.preferences[key] ?? fallback }
    func setPreference(_ key: String, value: Bool) {
        var updated = personal
        updated.preferences[key] = value
        _ = savePersonal(updated)
    }

    func markNotificationsRead(_ ids: [String]) {
        var updated = personal
        for id in ids { updated.preferences["notification.read.\(id)"] = true }
        _ = savePersonal(updated)
    }

    @discardableResult
    func saveFeedback(topic: String, message: String) -> Bool {
        let subject = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !body.isEmpty, subject.count <= 80, body.count <= 2000 else { return false }
        var updated = personal
        var feedback = updated.feedbackSubmissions ?? []
        feedback.append(NanaSavedFeedback(id: UUID().uuidString, topic: subject, message: body, createdAt: Date()))
        updated.feedbackSubmissions = feedback
        updated.drafts.removeValue(forKey: "feedback.topic")
        updated.drafts.removeValue(forKey: "feedback")
        guard savePersonal(updated) else { return false }
        drafts = updated.drafts
        actionNotice = AccountEntryNotice(title: "Feedback saved", explanation: "Your feedback has been saved on this device.")
        return true
    }

    func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func markRead(_ conversation: NanaConversation) {
        var updated = personal
        updated.readConversations[conversation.id] = conversationRevision(conversation)
        _ = savePersonal(updated)
    }

    func hideConversation(_ id: String) {
        var updated = personal
        updated.hiddenConversationIDs.insert(id)
        _ = savePersonal(updated)
    }

    @discardableResult
    func clearConversationList(showNotice: Bool = true) -> Bool {
        var updated = personal
        updated.hiddenConversationIDs.formUnion(visibleConversations.map(\.id))
        guard savePersonal(updated) else { return false }
        if showNotice {
            actionNotice = AccountEntryNotice(title: "Messages cleared", explanation: "This device's message list has been cleared.")
        }
        return true
    }

    func clearCache() {
        generation = UUID()
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        do {
            if let cacheURL, FileManager.default.fileExists(atPath: cacheURL.path) { try FileManager.default.removeItem(at: cacheURL) }
            payload = .empty
            fetchedAt = [:]
            states = [:]
            assetManifest = []
            URLCache.shared.removeAllCachedResponses()
            actionNotice = AccountEntryNotice(title: "Cache cleared", explanation: "Your photos, preferences, activity and coins are kept.")
        } catch {
            actionNotice = AccountEntryNotice(title: "Cache not cleared", explanation: "Please try again.")
        }
    }

    func photoURL(_ photo: NanaPersonalPhoto) -> URL? {
        personalURL?.deletingLastPathComponent().appendingPathComponent(photo.filename)
    }

    func addPhoto(_ data: Data, accountID: String?) {
        guard accountID == accountScope, accountID != nil, personalStorageReady,
              let directory = personalURL?.deletingLastPathComponent(), data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary), let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            actionNotice = AccountEntryNotice(title: "Photo not added", explanation: "Choose a photo smaller than 25 MB and try again.")
            return
        }
        let photo = NanaPersonalPhoto(id: UUID().uuidString, createdAt: Date())
        let destination = directory.appendingPathComponent(photo.filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var updated = personal
            updated.photos.append(photo)
            if !savePersonal(updated) { try? FileManager.default.removeItem(at: destination) }
        } catch {
            actionNotice = AccountEntryNotice(title: "Photo not added", explanation: "Nana couldn't save this photo. Please try again.")
        }
    }

    func deletePhotos(_ ids: Set<String>) {
        let removed = personal.photos.filter { ids.contains($0.id) }
        var updated = personal
        updated.photos.removeAll { ids.contains($0.id) }
        guard savePersonal(updated) else { return }
        for photo in removed { if let url = photoURL(photo) { try? FileManager.default.removeItem(at: url) } }
        actionNotice = AccountEntryNotice(title: "Photos deleted", explanation: "Selected photos were removed from this album.")
    }

    private func conversationRevision(_ value: NanaConversation) -> String {
        [value.sentAtLabel, value.preview, String(value.unreadCount)].joined(separator: "|")
    }

    /// Curate the bundled replay experience without changing real live streams.
    /// Reapply after every read so a refreshed four-room fixture cannot undo it.
    private func applyReplayCatalog() {
        let replacements = [
            "room-aurora": "nana.video.lilyrowland1_DdUO9QMRvap",
            "room-studio": "nana.video.maialopezr_Dcn_qDCoCUr"
        ]
        guard payload.rooms.contains(where: { replacements[$0.id] != nil && $0.streamSourceType == "simulatedReplay" }) else { return }
        for index in payload.rooms.indices {
            guard payload.rooms[index].streamSourceType == "simulatedReplay",
                  let asset = replacements[payload.rooms[index].id],
                  NanaAssetLibrary.videoURL(for: asset) != nil else { continue }
            payload.rooms[index].streamAssetKey = asset
        }
        let lin = payload.profiles.first { $0.id == "profile-lin" } ?? NanaProfile(
            id: "profile-lin", displayName: "Lin Wei", handle: "lin.w", region: "Singapore",
            language: "English", gender: "Female", age: 26, introduction: "Small stories from the city.",
            avatarAssetKey: "nana.pic.Dc1UKGTDL1J", isConnected: false, followerCount: 0, followingCount: 0, level: 3
        )
        let sienna = NanaProfile(
            id: "profile-replay-sienna", displayName: "Sienna Blake", handle: "sienna.b", region: "Vancouver",
            language: "English", gender: "Female", age: 28, introduction: "Fresh air and easy conversations.",
            avatarAssetKey: "nana.pic.DdQxT9NCkQ1", isConnected: false, followerCount: 0, followingCount: 0, level: 5
        )
        let additions: [(NanaProfile, NanaLiveRoom)] = [
            (lin, NanaLiveRoom(
                id: "room-city", title: "City catch-up", subtitle: "A walk, a story, a little company",
                category: "Open talk", hostID: lin.id, hostName: lin.displayName, hostAvatarAssetKey: lin.avatarAssetKey,
                viewerCount: 0, seatCapacity: 6, streamAssetKey: "nana.video.mkaaloha_DcJhc7MRaoo",
                streamSourceType: "simulatedReplay", roomState: "Live now", isFollowingHost: false
            )),
            (sienna, NanaLiveRoom(
                id: "room-outdoors", title: "Fresh air stories", subtitle: "Slow down and share your day",
                category: "Creative", hostID: sienna.id, hostName: sienna.displayName, hostAvatarAssetKey: sienna.avatarAssetKey,
                viewerCount: 0, seatCapacity: 6, streamAssetKey: "nana.video.inga_galeeva__DanUYxRMQMd",
                streamSourceType: "simulatedReplay", roomState: "Live now", isFollowingHost: false
            ))
        ]
        for (profile, room) in additions {
            guard let asset = room.streamAssetKey, NanaAssetLibrary.videoURL(for: asset) != nil else { continue }
            if !payload.rooms.contains(where: { $0.id == room.id }) { payload.rooms.append(room) }
            guard payload.rooms.contains(where: { $0.id == room.id && $0.streamSourceType == "simulatedReplay" }) else { continue }
            if !payload.profiles.contains(where: { $0.id == profile.id }) { payload.profiles.append(profile) }
            if !payload.roomSeats.contains(where: { $0.roomID == room.id }) {
                payload.roomSeats += (0..<room.seatCapacity).map { position in
                    NanaRoomSeat(
                        id: "\(room.id)-seat-\(position)", roomID: room.id, position: position,
                        profileID: position == 0 ? profile.id : nil, displayName: position == 0 ? profile.displayName : nil,
                        role: position == 0 ? "Host" : "Listener", isMuted: false, isInvited: false
                    )
                }
            }
        }
    }

    private func applyPersonalOverlays() {
        applyReplayCatalog()
        for index in payload.profiles.indices {
            if let following = personal.following[payload.profiles[index].id] { payload.profiles[index].isConnected = following }
        }
        for index in payload.rooms.indices {
            if let following = personal.following[payload.rooms[index].hostID] { payload.rooms[index].isFollowingHost = following }
        }
    }

    @discardableResult
    private func savePersonal(_ updated: NanaPersonalState) -> Bool {
        guard personalStorageReady, let personalURL else {
            actionNotice = AccountEntryNotice(title: "Changes not saved", explanation: "Your local storage isn't ready. Please reopen Nana and try again.")
            return false
        }
        do {
            var directory = personalURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(updated).write(to: personalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            personal = updated
            return true
        } catch {
            actionNotice = AccountEntryNotice(title: "Changes not saved", explanation: "Please try again. Your previous data is kept.")
            return false
        }
    }

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


/// Separate from disposable JSON snapshots; never sent to the content service.
struct NanaPersonalState: Codable {
    var feedbackSubmissions: [NanaSavedFeedback]? = nil
    var safetyPortraits: [String: Set<String>]? = nil
    var safetyReports: [NanaSafetyReport]? = nil
    var hiddenRoomIDs: Set<String>? = nil
    var reportedProfileIDs: Set<String>? = nil
    var safetyAuthorAliases: [String: Set<String>]? = nil
    var postComments: [String: [NanaPostComment]]? = nil
    var postReports: [NanaPostReport]? = nil
    var hiddenPostKeys: Set<String>? = nil
    var following: [String: Bool] = [:]
    var followedProfiles: [String: NanaProfile] = [:]
    var hiddenProfiles: [String: NanaProfile] = [:]
    var hiddenConversationIDs: Set<String> = []
    var readConversations: [String: String] = [:]
    var checkInDays: Set<String> = []
    var preferences: [String: Bool] = [:]
    var drafts: [String: String] = [:]
    var photos: [NanaPersonalPhoto] = []
}

struct NanaSavedFeedback: Codable, Identifiable {
    let id: String
    let topic: String
    let message: String
    let createdAt: Date
}

struct NanaPersonalPhoto: Codable, Identifiable {
    let id: String
    let createdAt: Date
    var filename: String { "photo-" + id + ".jpg" }
}
