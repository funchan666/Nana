import Foundation

struct NanaProfile: Identifiable, Codable, Hashable {
    /// Small, stable counts for the supplied replay cast, never live account data.
    static let replaySocialCounts: [String: (followers: Int, following: Int)] = [
        "profile-ava": (128, 36), "profile-jules": (76, 29),
        "profile-mira": (93, 41), "profile-noah": (164, 58),
        "profile-lin": (47, 23), "profile-replay-sienna": (62, 34)
    ]
    let id: String
    var displayName: String
    var handle: String
    var region: String
    var language: String
    var gender: String
    var age: Int
    var introduction: String
    var avatarAssetKey: String?
    var isConnected: Bool
    var followerCount: Int
    var followingCount: Int
    var level: Int
}

struct NanaLiveRoom: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var category: String
    var hostID: String
    var hostName: String
    var hostAvatarAssetKey: String?
    var viewerCount: Int
    var seatCapacity: Int
    var streamAssetKey: String?
    var streamSourceType: String?
    var roomState: String
    var isFollowingHost: Bool
}

/// Presentation-only audience for a bundled replay; never persisted as live membership.
struct NanaReplayAudienceMember: Identifiable {
    let id: String
    let displayName: String
    let avatarAssetKey: String
}

enum NanaRoomRole: String, Codable, Hashable {
    case host = "Host"
    case administrator = "Administrator"
    case listener = "Listener"
}

struct NanaRoomSeat: Identifiable, Codable, Hashable {
    let id: String
    let roomID: String
    let position: Int
    var profileID: String?
    var displayName: String?
    var role: String
    var isMuted: Bool
    var isInvited: Bool
}

struct NanaPost: Identifiable, Codable, Hashable {
    let id: String
    var authorID: String
    var authorName: String
    var title: String
    var body: String
    var category: String
    var coverAssetKey: String?
    var commentCount: Int
    var publishedLabel: String
}

struct NanaConversation: Identifiable, Codable, Hashable {
    let id: String
    var profileID: String
    var displayName: String
    var preview: String
    var sentAtLabel: String
    var unreadCount: Int
    var avatarAssetKey: String?
}

/// Account-authenticated inbox data, kept separate from the public catalog/cache.
/// Only a private messaging transport may provide this snapshot. Public fixture
/// profiles, follow flags and conversation examples are not evidence of friendship.
struct NanaAccountInboxSnapshot {
    let accountID: String
    let mutualFriends: [NanaProfile]
    let liveRooms: [NanaLiveRoom]
    let conversations: [NanaConversation]
    let messages: [NanaMessage]
    var newFollowers: [NanaProfile] = []
    var followers: [NanaProfile] = []
    var totalCallDurationSeconds: Int? = nil
    var missedCallCount: Int? = nil
}

struct NanaPostDiscussion {
    let key: String
    let title: String
    let authorID: String
    let authorName: String
    let authorAvatar: String?
    let videoAssetKey: String?
    var kind: NanaSafetyContentKind = .post
    var parentContentKey: String? = nil
    var commentID: String? = nil
}

enum NanaSafetyContentKind: String, Codable { case post, room, profile, conversation, comment }

struct NanaSafetyReport: Codable {
    let contentKey: String
    let kind: NanaSafetyContentKind
    let authorID: String
    let reason: String
    let createdAt: Date
    var parentContentKey: String? = nil
    var commentID: String? = nil
    var contentExcerpt: String? = nil
}

struct NanaPostComment: Identifiable, Codable {
    let id: String
    let authorID: String
    let authorName: String
    let avatarAssetKey: String?
    let body: String
    let timeLabel: String
}

struct NanaPostReport: Codable {
    let contentKey: String
    let reason: String
    let createdAt: Date
}

struct NanaMessage: Identifiable, Codable, Hashable {
    let id: String
    let conversationID: String
    let senderID: String
    let senderName: String
    let body: String
    let sentAtLabel: String
    let isFromCurrentUser: Bool
}

struct NanaVideoCallSession: Identifiable, Codable, Hashable {
    let id: String
    let callerID: String
    let recipientID: String
    var phase: String
    var startedAtLabel: String
    var localPreviewEnabled: Bool
}

struct NanaGift: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var coinCost: Int
    var assetKey: String?
}

extension NanaGift {
    /// The A-side gift catalog matches the supplied artwork and prices. Legacy
    /// photo-based feed gifts are not purchase identifiers for these room gifts.
    static let roomCatalog: [NanaGift] = [
        NanaGift(id: "gift-music-note", title: "Music note", coinCost: 0, assetKey: "nana.voice.voice_asset_077"),
        NanaGift(id: "gift-gamepad", title: "Gamepad", coinCost: 0, assetKey: "nana.voice.voice_asset_088"),
        NanaGift(id: "gift-karaoke", title: "Karaoke", coinCost: 29, assetKey: "nana.voice.voice_asset_089"),
        NanaGift(id: "gift-drum", title: "Drum", coinCost: 39, assetKey: "nana.voice.voice_asset_122"),
        NanaGift(id: "gift-headphones", title: "Headphones", coinCost: 49, assetKey: "nana.voice.voice_asset_090"),
        NanaGift(id: "gift-microphone", title: "Microphone", coinCost: 59, assetKey: "nana.voice.voice_asset_118"),
        NanaGift(id: "gift-record", title: "Record", coinCost: 69, assetKey: "nana.voice.voice_asset_091"),
        NanaGift(id: "gift-keyboard", title: "Keyboard", coinCost: 79, assetKey: "nana.voice.voice_asset_164")
    ]
}

struct NanaRoomChatMessage: Identifiable, Codable, Hashable {
    let id: String
    let roomID: String
    let senderName: String
    let body: String
    let sentAtLabel: String
    var senderID: String? = nil
}

/// A local room gift receipt. This is separate from server chat and gift delivery.
struct NanaRoomGiftReceipt: Identifiable, Codable, Hashable {
    let id: String
    let roomID: String
    let hostName: String
    let senderName: String
    let gift: NanaGift
    let quantity: Int
    let createdAt: Date

    var totalCoins: Int {
        let result = gift.coinCost.multipliedReportingOverflow(by: quantity)
        return result.overflow ? Int.max : result.partialValue
    }

    var chatMessage: NanaRoomChatMessage {
        NanaRoomChatMessage(
            id: "sent-gift-\(id)", roomID: roomID, senderName: senderName,
            body: "Sent \(gift.title) ×\(quantity) to \(hostName)",
            sentAtLabel: createdAt.formatted(date: .omitted, time: .shortened)
        )
    }
}

struct NanaSearchFilter: Codable, Hashable {
    var kind: SearchKind = .all
    var minimumAge: Int = 18
    var maximumAge: Int = 45
    var region: String = "All regions"
    var language: String = "All languages"
    var gender: String = "Any"

    enum SearchKind: String, Codable, CaseIterable, Hashable {
        case all = "All"
        case people = "People"
        case rooms = "Rooms"
        case posts = "Posts"
    }
}

struct NanaWalletSnapshot: Codable, Hashable {
    var coinBalance: Int
    var totalSpent: Int
    var roomContribution: Int
    var activityPoints: Int
    var level: Int
    var nextLevelPoints: Int
}

struct NanaModerationAction: Identifiable, Codable, Hashable {
    let id: String
    let actorID: String
    let targetID: String
    let roomID: String?
    var actionKind: String
    var reason: String
    var createdAtLabel: String
}

struct NanaCheckInRecord: Identifiable, Codable, Hashable {
    let id: String
    let accountID: String
    let checkInDateLabel: String
    var rewardPoints: Int
    var streakLength: Int
}

struct NanaInventoryAsset: Identifiable, Codable, Hashable {
    let id: String
    let accountID: String
    let assetKind: String
    let title: String
    var quantity: Int
    var expiresAtLabel: String?
}

struct NanaContentSnapshot: Codable {
    var profiles: [NanaProfile]
    var rooms: [NanaLiveRoom]
    var roomSeats: [NanaRoomSeat]
    var posts: [NanaPost]
    var conversations: [NanaConversation]
    var messages: [NanaMessage]
    var gifts: [NanaGift]
    var roomMessages: [NanaRoomChatMessage]
    var wallet: NanaWalletSnapshot
}

extension NanaContentSnapshot {
    static let empty = NanaContentSnapshot(profiles: [], rooms: [], roomSeats: [], posts: [], conversations: [], messages: [], gifts: [], roomMessages: [], wallet: NanaWalletSnapshot(coinBalance: 0, totalSpent: 0, roomContribution: 0, activityPoints: 0, level: 0, nextLevelPoints: 1))

    #if DEBUG
    static let sample: NanaContentSnapshot = {
        let profiles = [
            NanaProfile(id: "profile-ava", displayName: "Ava Monroe", handle: "ava.m", region: "Toronto", language: "English", gender: "Female", age: 27, introduction: "Music, late-night conversations, and small rooms with good energy.", avatarAssetKey: "nana.pic.Dc0SA4UiUy3", isConnected: false, followerCount: 128, followingCount: 36, level: 7),
            NanaProfile(id: "profile-jules", displayName: "Jules Harper", handle: "jules.h", region: "London", language: "English", gender: "Non-binary", age: 29, introduction: "A quiet corner for creative people and curious listeners.", avatarAssetKey: "nana.pic.Dc0XoT9DgeO", isConnected: false, followerCount: 76, followingCount: 29, level: 5),
            NanaProfile(id: "profile-mira", displayName: "Mira Laurent", handle: "mira.l", region: "Paris", language: "French", gender: "Female", age: 25, introduction: "Sharing stories, studio notes, and a little daylight.", avatarAssetKey: "nana.pic.Dc1CvDfCCHN", isConnected: false, followerCount: 93, followingCount: 41, level: 4),
            NanaProfile(id: "profile-noah", displayName: "Noah Reed", handle: "noah.r", region: "New York", language: "English", gender: "Male", age: 31, introduction: "Live sessions, headphones, and the occasional good question.", avatarAssetKey: "nana.pic.Dc1Ii5HACCq", isConnected: false, followerCount: 164, followingCount: 58, level: 6),
            NanaProfile(id: "profile-lin", displayName: "Lin Wei", handle: "lin.w", region: "Singapore", language: "Mandarin", gender: "Female", age: 26, introduction: "I host gentle rooms for people who like to stay awhile.", avatarAssetKey: "nana.pic.Dc1UKGTDL1J", isConnected: false, followerCount: 47, followingCount: 23, level: 3)
        ]
        let rooms = [
            NanaLiveRoom(id: "room-aurora", title: "Afterglow conversations", subtitle: "A soft place for unfinished thoughts", category: "Late night", hostID: "profile-ava", hostName: "Ava Monroe", hostAvatarAssetKey: "nana.pic.Dc0SA4UiUy3", viewerCount: 186, seatCapacity: 6, streamAssetKey: "nana.video.ariffathulhakim_Dbzl1fLurT2", streamSourceType: "simulatedReplay", roomState: "Live now", isFollowingHost: false),
            NanaLiveRoom(id: "room-studio", title: "Studio notes", subtitle: "Playlists, process, and quiet work", category: "Creative", hostID: "profile-jules", hostName: "Jules Harper", hostAvatarAssetKey: "nana.pic.Dc0XoT9DgeO", viewerCount: 93, seatCapacity: 9, streamAssetKey: "nana.video.berniemor_DddsSyxCRiE", streamSourceType: "simulatedReplay", roomState: "Live now", isFollowingHost: false),
            NanaLiveRoom(id: "room-lantern", title: "The lantern table", subtitle: "Come in, listen for a while", category: "Open talk", hostID: "profile-mira", hostName: "Mira Laurent", hostAvatarAssetKey: "nana.pic.Dc1CvDfCCHN", viewerCount: 68, seatCapacity: 3, streamAssetKey: "nana.video.capt.carterbrown_DbYh5-rhrZj", streamSourceType: "simulatedReplay", roomState: "Live now", isFollowingHost: false),
            NanaLiveRoom(id: "room-midnight", title: "Midnight radio", subtitle: "One song, one story, one new voice", category: "Music", hostID: "profile-noah", hostName: "Noah Reed", hostAvatarAssetKey: "nana.pic.Dc1Ii5HACCq", viewerCount: 242, seatCapacity: 12, streamAssetKey: "nana.video.coletrotta_DbWqTuiPTGg", streamSourceType: "simulatedReplay", roomState: "Live now", isFollowingHost: false)
        ]
        let seats = rooms.flatMap { room in
            (0..<room.seatCapacity).map { index in
                NanaRoomSeat(id: "\(room.id)-seat-\(index)", roomID: room.id, position: index, profileID: index == 0 ? room.hostID : nil, displayName: index == 0 ? room.hostName : nil, role: index == 0 ? "Host" : "Listener", isMuted: false, isInvited: false)
            }
        }
        let posts = [
            NanaPost(id: "post-echoes", authorID: "profile-ava", authorName: "Ava Monroe", title: "What makes a room feel safe?", body: "I keep thinking it is not the number of people. It is the way someone leaves a little space for the next voice.", category: "Room culture", coverAssetKey: "nana.pic.Dc1fyTwF2Hv", commentCount: 28, publishedLabel: "12 min ago"),
            NanaPost(id: "post-studio", authorID: "profile-jules", authorName: "Jules Harper", title: "Three songs for a slow afternoon", body: "A small listening list for when you want the day to move at a different pace.", category: "Music", coverAssetKey: "nana.pic.Dc2AwHAjPnJ", commentCount: 14, publishedLabel: "1 hr ago"),
            NanaPost(id: "post-question", authorID: "profile-lin", authorName: "Lin Wei", title: "A question for the next room", body: "What is something you learned from a stranger that stayed with you?", category: "Community", coverAssetKey: "nana.pic.Dc3eSgKCMLY", commentCount: 42, publishedLabel: "Yesterday"),
        ]
        let conversations = [
            NanaConversation(id: "conversation-ava", profileID: "profile-ava", displayName: "Ava Monroe", preview: "I saved you a seat in the afterglow room.", sentAtLabel: "8 min", unreadCount: 2, avatarAssetKey: "nana.pic.Dc0SA4UiUy3"),
            NanaConversation(id: "conversation-jules", profileID: "profile-jules", displayName: "Jules Harper", preview: "That playlist made the room feel warmer.", sentAtLabel: "Yesterday", unreadCount: 0, avatarAssetKey: "nana.pic.Dc0XoT9DgeO"),
            NanaConversation(id: "conversation-lin", profileID: "profile-lin", displayName: "Lin Wei", preview: "See you in the next conversation.", sentAtLabel: "Mon", unreadCount: 0, avatarAssetKey: "nana.pic.Dc1CvDfCCHN")
        ]
        let messages = [
            NanaMessage(id: "message-1", conversationID: "conversation-ava", senderID: "profile-ava", senderName: "Ava Monroe", body: "I saved you a seat in the afterglow room.", sentAtLabel: "8 min", isFromCurrentUser: false),
            NanaMessage(id: "message-2", conversationID: "conversation-ava", senderID: "local", senderName: "You", body: "I will be there soon.", sentAtLabel: "6 min", isFromCurrentUser: true)
        ]
        let gifts = NanaGift.roomCatalog
        let roomMessages = [
            NanaRoomChatMessage(id: "room-message-1", roomID: "room-aurora", senderName: "Mira", body: "This question is staying with me.", sentAtLabel: "now"),
            NanaRoomChatMessage(id: "room-message-2", roomID: "room-aurora", senderName: "Jules", body: "Same here. I like how slow this room feels.", sentAtLabel: "now")
        ]
        return NanaContentSnapshot(profiles: profiles, rooms: rooms, roomSeats: seats, posts: posts, conversations: conversations, messages: messages, gifts: gifts, roomMessages: roomMessages, wallet: NanaWalletSnapshot(coinBalance: 1231, totalSpent: 3840, roomContribution: 820, activityPoints: 1320, level: 7, nextLevelPoints: 2200))
    }()
    #endif
}
