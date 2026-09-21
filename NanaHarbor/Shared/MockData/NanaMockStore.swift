import Foundation
import Combine

@MainActor
final class NanaMockStore: ObservableObject {
    @Published private(set) var payload: NanaMockPayload
    @Published var selectedCategory: String = "For you"
    @Published var searchFilter = NanaSearchFilter()
    @Published private(set) var checkedInToday = false
    @Published private(set) var blockedProfileIDs: Set<String>

    private let defaults: UserDefaults
    private let persistedPayloadKey = "nana.mock.payload.v1"
    private let checkedInKey = "nana.mock.checkedIn.v1"
    private let blockedProfilesKey = "nana.mock.blockedProfiles.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.data(forKey: persistedPayloadKey), let decoded = try? JSONDecoder().decode(NanaMockPayload.self, from: saved) {
            payload = decoded
        } else if let url = Bundle.main.url(forResource: "NanaMockPayload", withExtension: "json"), let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(NanaMockPayload.self, from: data) {
            payload = decoded
        } else {
            payload = .sample
        }
        checkedInToday = defaults.bool(forKey: checkedInKey)
        blockedProfileIDs = Set(defaults.stringArray(forKey: blockedProfilesKey) ?? [])
    }

    var categories: [String] { ["For you", "Following", "Late night", "Creative", "Music", "Open talk"] }

    func room(with id: String) -> NanaLiveRoom? {
        payload.rooms.first(where: { $0.id == id })
    }

    func profile(with id: String) -> NanaProfile? {
        payload.profiles.first(where: { $0.id == id })
    }

    func posts(for filter: NanaSearchFilter? = nil) -> [NanaPost] {
        guard let filter else { return payload.posts }
        switch filter.kind {
        case .all, .posts: return payload.posts
        case .people, .rooms: return []
        }
    }

    func filteredProfiles(for filter: NanaSearchFilter) -> [NanaProfile] {
        payload.profiles.filter { profile in
            guard !blockedProfileIDs.contains(profile.id) else { return false }
            let matchesAge = profile.age >= filter.minimumAge && profile.age <= filter.maximumAge
            let matchesRegion = filter.region == "All regions" || profile.region == filter.region
            let matchesLanguage = filter.language == "All languages" || profile.language == filter.language
            let matchesGender = filter.gender == "Any" || profile.gender == filter.gender
            return matchesAge && matchesRegion && matchesLanguage && matchesGender
        }
    }

    func filteredRooms(for filter: NanaSearchFilter) -> [NanaLiveRoom] {
        payload.rooms.filter { room in
            guard !blockedProfileIDs.contains(room.hostID) else { return false }
            if filter.kind == .people || filter.kind == .posts { return false }
            return filter.kind == .all || filter.kind == .rooms || room.category == selectedCategory || selectedCategory == "For you" || selectedCategory == "Following"
        }
    }

    func block(profileID: String) {
        blockedProfileIDs.insert(profileID)
        defaults.set(Array(blockedProfileIDs), forKey: blockedProfilesKey)
        persist()
    }

    func toggleConnection(for profileID: String) {
        guard let index = payload.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        payload.profiles[index].isConnected.toggle()
        let connected = payload.profiles[index].isConnected
        for index in payload.rooms.indices where payload.rooms[index].hostID == profileID {
            payload.rooms[index].isFollowingHost = connected
        }
        persist()
    }

    func appendMessage(to conversationID: String, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        payload.messages.append(NanaMessage(id: UUID().uuidString, conversationID: conversationID, senderID: "local", senderName: "You", body: trimmed, sentAtLabel: "now", isFromCurrentUser: true))
        if let index = payload.conversations.firstIndex(where: { $0.id == conversationID }) {
            payload.conversations[index].preview = trimmed
            payload.conversations[index].sentAtLabel = "now"
            payload.conversations[index].unreadCount = 0
        }
        persist()
    }

    func appendRoomMessage(roomID: String, body: String, senderName: String = "You") {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        payload.roomMessages.append(NanaRoomChatMessage(id: UUID().uuidString, roomID: roomID, senderName: senderName, body: trimmed, sentAtLabel: "now"))
        persist()
    }

    func toggleMute(roomID: String, seatID: String) {
        guard let index = payload.roomSeats.firstIndex(where: { $0.roomID == roomID && $0.id == seatID }) else { return }
        payload.roomSeats[index].isMuted.toggle()
        persist()
    }

    func kick(roomID: String, seatID: String) {
        guard let index = payload.roomSeats.firstIndex(where: { $0.roomID == roomID && $0.id == seatID }) else { return }
        payload.roomSeats[index].profileID = nil
        payload.roomSeats[index].displayName = nil
        payload.roomSeats[index].role = "Listener"
        payload.roomSeats[index].isMuted = false
        persist()
    }

    func sendGift(_ gift: NanaGift, to roomID: String) -> Bool {
        guard payload.wallet.coinBalance >= gift.coinCost else { return false }
        payload.wallet.coinBalance -= gift.coinCost
        payload.wallet.totalSpent += gift.coinCost
        payload.wallet.roomContribution += gift.coinCost
        payload.wallet.activityPoints += 12
        payload.roomMessages.append(NanaRoomChatMessage(id: UUID().uuidString, roomID: roomID, senderName: "You", body: "Sent \(gift.title)", sentAtLabel: "now"))
        persist()
        return true
    }

    func performCheckIn() {
        guard !checkedInToday else { return }
        checkedInToday = true
        payload.wallet.activityPoints += 80
        defaults.set(true, forKey: checkedInKey)
        persist()
    }

    func resetLocalMock() {
        payload = .sample
        checkedInToday = false
        defaults.removeObject(forKey: persistedPayloadKey)
        defaults.removeObject(forKey: checkedInKey)
        blockedProfileIDs.removeAll()
        defaults.removeObject(forKey: blockedProfilesKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: persistedPayloadKey)
    }
}
