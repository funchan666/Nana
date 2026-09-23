import SwiftUI
import PhotosUI
import UIKit

struct WarmThreadsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedConversation: NanaConversation?
    @State private var selectedFriendRoom: NanaLiveRoom?
    @State private var showingNoticeCenter = false
    @State private var showingFriends = false
    @State private var showingRanking = false
    @State private var showingSearch = false
    @State private var showingAlbum = false
    @State private var showingClearConfirmation = false
    @State private var pendingDeletion: NanaConversation?
    @State private var revealedConversationID: String?

    private var visibleConversations: [NanaConversation] {
        contentStore.visibleConversations
    }

    private var friendRooms: [NanaLiveRoom] {
        contentStore.liveFriendRooms
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        messagesHeader
                        messageSearch
                        shortcutRail
                        friendRoom
                        chatList
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 116)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedConversation) { conversation in NanaConversationView(conversation: conversation) }
            .fullScreenCover(item: $selectedFriendRoom) { room in NanaLiveRoomView(room: room) }
            .fullScreenCover(isPresented: $showingNoticeCenter) { NanaNotificationCenterView() }
            .fullScreenCover(isPresented: $showingFriends) { NanaFriendsListView() }
            .fullScreenCover(isPresented: $showingRanking) { NanaRankingView() }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
            .fullScreenCover(isPresented: $showingAlbum) { NanaAlbumGalleryView() }
            .sheet(isPresented: $showingClearConfirmation) {
                NanaClearConversationsSheet()
            }
            .alert(item: $pendingDeletion) { conversation in
                Alert(
                    title: Text("Remove conversation?"),
                    message: Text("This conversation will be hidden from this device's chat list."),
                    primaryButton: .destructive(Text("Remove")) {
                        contentStore.hideConversation(conversation.id)
                        revealedConversationID = nil
                    },
                    secondaryButton: .cancel()
                )
            }
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
        }
    }

    private var messagesHeader: some View {
        HStack(spacing: 2) {
            Text("Messages")
                .font(.system(size: 19, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            Spacer()
            Button { showingAlbum = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_108", contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .background(NanaPalette.deepSpace.opacity(0.6), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Personal album")
            Button { showingClearConfirmation = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_107", contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .background(NanaPalette.deepSpace.opacity(0.6), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear chat list")
            .disabled(visibleConversations.isEmpty)
            .opacity(visibleConversations.isEmpty ? 0.4 : 1)
        }
    }

    private var messageSearch: some View {
        Button { showingSearch = true } label: {
            HStack(spacing: 9) {
                Text("Please enter search content")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(NanaPalette.mutedWhite)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(height: 37)
            .background(NanaPalette.deepSpace.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(NanaPalette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutRail: some View {
        HStack(spacing: 9) {
            messageShortcut(title: "Notice", assetKey: "nana.voice.message_notice", action: { showingNoticeCenter = true })
            messageShortcut(title: "Friend List", assetKey: "nana.voice.message_friends", action: { showingFriends = true })
            messageShortcut(title: "Ranking", assetKey: "nana.voice.message_ranking", action: { showingRanking = true })
        }
    }

    private func messageShortcut(title: String, assetKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // These slices already include their labels and the complete tilted panel.
            NanaAssetImage(assetKey: assetKey, contentMode: .fit)
                .aspectRatio(234.0 / 142.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func hasLiveRoom(profileID: String) -> Bool {
        friendRooms.contains { $0.hostID == profileID }
    }

    private var friendRoom: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Friends live now")
                .font(.system(size: 13, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            if friendRooms.isEmpty {
                NanaInboxEmptyState(kind: .friendsLive) { showingFriends = true }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 17) {
                        ForEach(friendRooms) { room in
                            Button { selectedFriendRoom = room } label: {
                                VStack(spacing: 7) {
                                    NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 57)
                                        .overlay(Circle().stroke(NanaPalette.softPink, lineWidth: 1.5))
                                        .overlay(alignment: .bottom) {
                                            NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                                                .frame(width: 32, height: 11)
                                                .offset(y: 2)
                                        }
                                    Text(room.hostName.split(separator: " ").first.map(String.init) ?? room.hostName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(NanaPalette.warmWhite)
                                        .lineLimit(1)
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Join \(room.hostName)'s live room")
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var chatList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat List")
                .font(.system(size: 13, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            if visibleConversations.isEmpty {
                NanaInboxEmptyState(kind: .conversations) { showingSearch = true }
            } else {
                VStack(spacing: 12) {
                    ForEach(visibleConversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
        }
        .padding(.top, 3)
    }

    private func conversationRow(_ conversation: NanaConversation) -> some View {
        let isRevealed = revealedConversationID == conversation.id
        return ZStack(alignment: .trailing) {
            if isRevealed {
                Button { pendingDeletion = conversation } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_159", contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove conversation with \(conversation.displayName)")
            }
            Button {
                if isRevealed { revealedConversationID = nil }
                else { selectedConversation = conversation }
            } label: {
                HStack(spacing: 10) {
                    NanaAvatarView(title: conversation.displayName, assetKey: conversation.avatarAssetKey, size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(conversation.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(NanaPalette.warmWhite)
                                .lineLimit(1)
                            if hasLiveRoom(profileID: conversation.profileID) {
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                                    .frame(width: 29, height: 10)
                            }
                        }
                        Text(conversation.preview)
                            .font(.system(size: 11))
                            .foregroundStyle(NanaPalette.mutedWhite)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(conversation.sentAtLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(NanaPalette.mutedWhite)
                            .lineLimit(1)
                        if conversation.unreadCount > 0 {
                            Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Color(red: 1, green: 0.39, blue: 0.43), in: Capsule())
                        } else {
                            Color.clear.frame(width: 17, height: 17)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: isRevealed ? -52 : 0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 30 else { return }
                        revealedConversationID = value.translation.width < 0 ? conversation.id : nil
                    }
            )
            .accessibilityAction(named: Text("Remove conversation")) { pendingDeletion = conversation }
        }
        .clipped()
        .animation(.easeOut(duration: 0.2), value: isRevealed)
    }

}

/// The two empty states share original artwork styling, but keep distinct layouts
/// so an empty inbox doesn't look like a stack of notification banners.
private struct NanaInboxEmptyState: View {
    enum Kind { case friendsLive, conversations }

    let kind: Kind
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLive: Bool { kind == .friendsLive }
    private var title: String { isLive ? "No friends on air" : "Your next hello starts here" }
    private var detail: String {
        isLive
            ? "Live rooms from mutual friends will appear here."
            : "No conversations yet. Find someone you’d like to get to know."
    }

    var body: some View {
        Group {
            if isLive && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 9) {
                        copy(alignment: .leading)
                        actionButton
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    artwork(size: 108)
                }
                .padding(.vertical, 17)
                .padding(.leading, 20)
                .padding(.trailing, 10)
            } else {
                VStack(spacing: 0) {
                    artwork(size: isLive ? 112 : 150)
                        .padding(.bottom, 6)
                    copy(alignment: .center)
                    actionButton.padding(.top, 15)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isLive
                      ? Color(red: 0.12, green: 0.07, blue: 0.20).opacity(0.90)
                      : Color(red: 0.06, green: 0.045, blue: 0.095).opacity(0.94))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(red: 0.68, green: 0.48, blue: 0.87).opacity(isLive ? 0.19 : 0.11), lineWidth: 0.75)
        }
    }

    private func artwork(size: CGFloat) -> some View {
        // Transparent, bespoke Nana illustrations; no system-symbol substitute.
        Image(isLive ? "NanaEmptyFriendsLive" : "NanaEmptyConversations")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func copy(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 7) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(NanaPalette.warmWhite)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.footnote)
                .lineSpacing(3)
                .foregroundStyle(Color(red: 0.69, green: 0.65, blue: 0.77))
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var actionButton: some View {
        Button(action: action) {
            Text(isLive ? "View friends" : "Find people")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(isLive ? NanaPalette.electricLilac : .white)
                .padding(.horizontal, isLive ? 17 : 30)
                .frame(minHeight: 44)
                .background(isLive ? NanaPalette.violet.opacity(0.16) : NanaPalette.violet, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct NanaClearConversationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var cleared = false
    @State private var errorMessage: String?

    private let surface = Color(red: 0.075, green: 0.055, blue: 0.105)
    private var conversationCount: Int { contentStore.visibleConversations.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(NanaPalette.violet.opacity(0.16))
                    if cleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(NanaPalette.electricLilac)
                    } else {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_107", contentMode: .fit)
                            .frame(width: 34, height: 34)
                    }
                }
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NanaPalette.mutedWhite)
                        .frame(width: 44, height: 44)
                        .background(NanaPalette.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(cleared ? "Chat list cleared" : "Clear chat list?")
                        .font(.system(size: 25, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(cleared
                         ? "Your conversations have been hidden on this device."
                         : "Hide all conversations from your chat list on this device.")
                        .font(.system(size: 14))
                        .foregroundStyle(NanaPalette.mutedWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(NanaPalette.electricLilac)
                        Text(cleared ? "Messages are not deleted." : "\(conversationCount) \(conversationCount == 1 ? "conversation" : "conversations") · Messages stay saved")
                            .font(.system(size: 12, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NanaPalette.card, in: RoundedRectangle(cornerRadius: 14))
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(NanaPalette.warning)
                            .accessibilityLabel("Unable to clear chat list. \(errorMessage)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            actions
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .background(surface)
        .preferredColorScheme(.dark)
        .presentationDetents([.height(390), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(surface)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if !cleared {
                Button { dismiss() } label: {
                    Text("Keep chats")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(NanaPalette.cardStrong, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button {
                if cleared {
                    dismiss()
                } else if contentStore.clearConversationList(showNotice: false) {
                    errorMessage = nil
                    cleared = true
                } else {
                    errorMessage = contentStore.actionNotice?.explanation ?? "Please try again. Your chat list has not changed."
                    contentStore.dismissActionNotice()
                }
            } label: {
                Text(cleared ? "Done" : "Clear list")
                    .foregroundStyle(cleared ? NanaPalette.warmWhite : NanaPalette.midnight)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(cleared ? NanaPalette.violet : NanaPalette.warning, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!cleared && conversationCount == 0)
            .opacity(!cleared && conversationCount == 0 ? 0.4 : 1)
        }
        .font(.system(size: 15, weight: .semibold))
    }
}

// Native detail pages share the reference's compact 44pt navigation, charcoal
// rows, and full-display red/violet artwork; page content owns its own layout.
struct NanaDetailPageHeader: View {
    var title = ""
    var trailingTitle: String? = nil
    var trailingSymbol: String? = nil
    var trailingLabel = ""
    var trailingAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NanaPalette.warmWhite)
                .lineLimit(1)
                .padding(.horizontal, 58)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left.circle")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                if let trailingAction {
                    Button(action: trailingAction) {
                        Group {
                            if let trailingTitle {
                                Text(trailingTitle).font(.system(size: 14))
                            } else if let trailingSymbol {
                                Image(systemName: trailingSymbol).font(.system(size: 19))
                            } else {
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_107", contentMode: .fit)
                                    .frame(width: 25, height: 25)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trailingLabel)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

struct NanaInboxNotification: Identifiable {
    let id: String
    let title: String
    let summary: String
    let paragraphs: [String]

    static let notices: [Self] = [
        Self(id: "community-guidance", title: "Platform Notification",
             summary: "A welcoming community starts with respect.", paragraphs: [
                "Make room for different voices. Be respectful in live rooms, voice conversations and private messages, even when you disagree.",
                "Harassment, threats, hateful content, impersonation and scams do not belong here. Use Report on the relevant content or profile when something needs attention.",
                "You can block someone to stop seeing their content in Nana. Leave any room or conversation that makes you uncomfortable."
             ]),
        Self(id: "privacy-reminder", title: "Platform Notification",
             summary: "Keep your personal information safe.", paragraphs: [
                "Share thoughtfully. Avoid posting your address, passwords, payment details or other sensitive information in rooms, photos and messages.",
                "Be cautious with unexpected links and requests for money. Never share a verification code with another person.",
                "If someone pressures you or sends unwanted content, use Report or Block from their profile or the content's menu."
             ])
    ]
}

struct NanaNotificationCenterView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedNotice: NanaInboxNotification?

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                VStack(spacing: 0) {
                    NanaDetailPageHeader(title: "System Notification", trailingLabel: "Mark all as read") {
                        contentStore.markNotificationsRead(NanaInboxNotification.notices.map(\.id))
                    }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(NanaInboxNotification.notices) { notice in
                                notificationRow(notice)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedNotice) { notice in
                NanaNotificationDetailView(notice: notice)
            }
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func notificationRow(_ notice: NanaInboxNotification) -> some View {
        let unread = !contentStore.preference("notification.read.\(notice.id)", default: false)
        return Button {
            contentStore.markNotificationsRead([notice.id])
            selectedNotice = notice
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text(notice.title).font(.system(size: 14, weight: .medium))
                    if unread {
                        Text("New").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                Text(notice.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(NanaPalette.warmWhite)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct NanaNotificationDetailView: View {
    let notice: NanaInboxNotification

    var body: some View {
        ZStack {
            NanaTabBackdrop()
            VStack(spacing: 0) {
                NanaDetailPageHeader(title: "Notification details")
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(notice.title)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(NanaPalette.warmWhite)
                        ForEach(notice.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.system(size: 14))
                                .foregroundStyle(NanaPalette.mutedWhite)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaFriendsListView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedProfile: NanaProfile?
    @State private var selectedConversation: NanaConversation?
    @State private var showingNew = false
    @State private var callProfile: NanaProfile?

    private var profiles: [NanaProfile] {
        showingNew ? contentStore.newFollowers : contentStore.mutualFriends
    }

    private var callDuration: String {
        guard let seconds = contentStore.accountInbox?.totalCallDurationSeconds else { return "—" }
        let value = max(0, seconds)
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    private var missedCalls: String {
        guard let count = contentStore.accountInbox?.missedCallCount else { return "—" }
        return String(max(0, count))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                VStack(spacing: 0) {
                    NanaDetailPageHeader()
                        .overlay(alignment: .top) {
                            HStack(spacing: 30) {
                                friendTab("Friends", selected: !showingNew) { showingNew = false }
                                friendTab("New", selected: showingNew) { showingNew = true }
                            }
                        }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            if !showingNew {
                                HStack(spacing: 10) {
                                    friendStat("Friend", "\(contentStore.mutualFriends.count)", color: .green)
                                    friendStat("Call duration", callDuration, color: .cyan)
                                    friendStat("Missed", missedCalls, color: .orange)
                                }
                                .padding(.bottom, 2)
                            }
                            if profiles.isEmpty {
                                NanaEmptyState(title: showingNew ? "No new followers" : "No friends yet",
                                               detail: showingNew ? "New followers will appear here." : "Follow each other to become friends.",
                                               actionTitle: nil, action: nil)
                                    .padding(.top, 48)
                            } else {
                                ForEach(profiles) { profile in
                                    if showingNew { newFollowerRow(profile) }
                                    else { friendRow(profile) }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedProfile) { NanaUserProfileView(profile: $0) }
            .sheet(item: $callProfile) { NanaVideoCallView(profile: $0) }
            .fullScreenCover(item: $selectedConversation) { NanaConversationView(conversation: $0) }
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func friendStat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private func friendTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(title).font(.system(size: 17, weight: .heavy).italic())
                    .foregroundStyle(selected ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
                Capsule().fill(selected ? NanaPalette.violet : .clear).frame(width: 28, height: 3)
            }
            .frame(minWidth: 64, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func friendRow(_ profile: NanaProfile) -> some View {
        HStack(spacing: 10) {
            Button { selectedProfile = profile } label: {
                NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 50)
                    .overlay(Circle().stroke(NanaPalette.neonPink, lineWidth: 1.5))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.displayName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text("\(profile.region) · Lv.\(profile.level)")
                    .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                Text("Mutual follow").font(.system(size: 10)).foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                friendAction("envelope.fill", color: NanaPalette.neonPink, label: "Message \(profile.displayName)") {
                    if let conversation = contentStore.visibleConversations.first(where: { $0.profileID == profile.id }) {
                        selectedConversation = conversation
                    } else { contentStore.explainUnavailable("Starting a private conversation") }
                }
                friendAction("video.fill", color: NanaPalette.violet, label: "Call \(profile.displayName)") { callProfile = profile }
            }
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(12)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 14))
    }

    private func newFollowerRow(_ profile: NanaProfile) -> some View {
        Button { selectedProfile = profile } label: {
            HStack(spacing: 12) {
                Group {
                    if let asset = profile.avatarAssetKey {
                        NanaAssetImage(assetKey: asset)
                    } else {
                        NanaAvatarView(title: profile.displayName, assetKey: nil, size: 68)
                    }
                }
                .frame(width: 72, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(NanaPalette.electricLilac, lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Text("\(profile.age) · \(profile.region) · Lv.\(profile.level)")
                        .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                    Text(profile.introduction).font(.system(size: 12))
                        .foregroundStyle(NanaPalette.mutedWhite).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(NanaPalette.violet, in: RoundedRectangle(cornerRadius: 11))
            }
            .foregroundStyle(NanaPalette.warmWhite)
            .padding(12)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private func friendAction(_ symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15))
                .frame(width: 34, height: 34).background(color, in: Circle())
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct NanaAlbumGalleryView: View {
    var profile: NanaProfile? = nil
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var isSelecting = false
    @State private var selectedAssets: Set<String> = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var previewPhoto: NanaPersonalPhoto?
    @State private var isImporting = false

    private var photos: [NanaPersonalPhoto] {
        // Another person's album must not expose this account's private photos.
        profile == nil ? contentStore.personal.photos : []
    }
    private var photoDays: [Date] {
        Set(photos.map { Calendar.current.startOfDay(for: $0.createdAt) }).sorted(by: >)
    }
    private var allSelected: Bool { !photos.isEmpty && selectedAssets.count == photos.count }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                VStack(spacing: 0) {
                    header
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.map { "\($0.displayName)'s Album" } ?? "Personal Album")
                                    .font(.system(size: 22, weight: .heavy).italic())
                                    .foregroundStyle(NanaPalette.warmWhite)
                                Text(profile == nil ? "All your uploaded photos, in one place." : "Photos shared by this person.")
                                    .font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                            }
                            if photos.isEmpty { emptyAlbum }
                            ForEach(photoDays, id: \.self) { day in
                                photoSection(day)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if profile == nil { albumActions }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                let accountID = contentStore.accountScope
                isImporting = true
                Task { @MainActor in
                    defer { selectedPhoto = nil; isImporting = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        guard contentStore.accountScope == accountID else { return }
                        contentStore.addPhoto(data, accountID: accountID)
                    } catch {
                        guard contentStore.accountScope == accountID else { return }
                        contentStore.actionNotice = AccountEntryNotice(title: "Photo not added", explanation: "Please choose another photo and try again.")
                    }
                }
            }
            .onChange(of: contentStore.personal.photos.map(\.id)) { _, ids in
                selectedAssets.formIntersection(Set(ids))
                if ids.isEmpty { isSelecting = false }
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    NanaPersonalPhotoImage(url: contentStore.photoURL(photo), contentMode: .fit)
                        .padding(.vertical, 64)
                    VStack {
                        NanaDetailPageHeader(title: "Photo")
                        Spacer()
                    }
                }.preferredColorScheme(.dark)
            }
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        Group {
            if profile == nil && !photos.isEmpty {
                NanaDetailPageHeader(trailingTitle: isSelecting ? "Done" : "Choice", trailingLabel: isSelecting ? "Finish selecting" : "Select photos") {
                    isSelecting.toggle()
                    selectedAssets.removeAll()
                }
            } else {
                NanaDetailPageHeader()
            }
        }
    }

    private var emptyAlbum: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(NanaPalette.electricLilac)
                .frame(width: 88, height: 88)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            Text("No photos yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NanaPalette.warmWhite)
            Text(profile == nil ? "Add a moment you'd like to keep." : "Shared photos will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(NanaPalette.mutedWhite)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private func photoSection(_ day: Date) -> some View {
        let dayPhotos = photos.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
            .sorted { $0.createdAt > $1.createdAt }
        return VStack(alignment: .leading, spacing: 12) {
            Text(day.formatted(date: .numeric, time: .omitted))
                .font(.system(size: 13))
                .foregroundStyle(NanaPalette.mutedWhite)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(dayPhotos) { photo in
                    photoTile(photo)
                }
            }
        }
    }

    private func photoTile(_ photo: NanaPersonalPhoto) -> some View {
        Button {
            if isSelecting {
                if !selectedAssets.insert(photo.id).inserted { selectedAssets.remove(photo.id) }
            } else { previewPhoto = photo }
        } label: {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        NanaPersonalPhotoImage(url: contentStore.photoURL(photo))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: selectedAssets.contains(photo.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(selectedAssets.contains(photo.id) ? NanaPalette.violet : .white)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelecting ? "Select photo" : "Open photo")
        .accessibilityAddTraits(selectedAssets.contains(photo.id) ? .isSelected : [])
    }

    private var albumActions: some View {
        HStack(spacing: 16) {
            if isSelecting {
                Button {
                    selectedAssets = allSelected ? [] : Set(photos.map(\.id))
                } label: {
                    Label("Select all", systemImage: allSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(NanaPalette.warmWhite)
                        .frame(minHeight: 48)
                }.buttonStyle(.plain)
                Button {
                    contentStore.deletePhotos(selectedAssets)
                } label: {
                    Text("Delete selected (\(selectedAssets.count))")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(NanaPalette.violet, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedAssets.isEmpty)
                .opacity(selectedAssets.isEmpty ? 0.45 : 1)
            } else {
                Spacer(minLength: 20)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 8) {
                        if isImporting { ProgressView().tint(.white) }
                        Text(isImporting ? "Adding photo…" : "Upload photo")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(NanaPalette.violet, in: Capsule())
                }
                .disabled(isImporting)
                Spacer(minLength: 20)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

private struct NanaPersonalPhotoImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    NanaPalette.cardStrong
                    Image(systemName: "photo").foregroundStyle(NanaPalette.mutedWhite)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct NanaConversationView: View {
    let conversation: NanaConversation
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var draft = ""
    @State private var draftAccountID: String?
    @State private var showingCall = false
    @State private var showingProfile = false
    @State private var showingMore = false
    @State private var showingAccessories = false
    @State private var showingEmoji = false
    @State private var pendingSafetyAction: NanaPostSafetyAction?
    @State private var safetyAction: NanaPostSafetyAction?
    @FocusState private var composerFocused: Bool

    private var messages: [NanaMessage] { contentStore.conversationMessages(for: conversation.id) }
    private var profile: NanaProfile? { contentStore.profile(with: conversation.profileID) }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var draftKey: String { "conversation.\(conversation.id)" }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                VStack(spacing: 0) {
                    NanaDetailPageHeader(trailingSymbol: "ellipsis.circle", trailingLabel: "Conversation options") {
                        composerFocused = false
                        showingMore = true
                    }
                    messageHistory
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                draftAccountID = contentStore.accountScope
                draft = contentStore.draft(for: draftKey)
                contentStore.markRead(conversation)
            }
            .onDisappear {
                if draftAccountID != nil && draftAccountID == contentStore.accountScope {
                    _ = contentStore.saveDraft(draft, for: draftKey)
                }
            }
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
            .sheet(isPresented: $showingProfile) {
                if let profile { NanaUserProfileView(profile: profile) }
            }
            .sheet(isPresented: $showingCall) {
                if let profile { NanaVideoCallView(profile: profile) }
                else { NanaUnavailableSurface(title: "Profile unavailable", detail: "Please try again later.") }
            }
            .sheet(isPresented: $showingMore, onDismiss: {
                safetyAction = pendingSafetyAction
                pendingSafetyAction = nil
            }) { conversationOptions }
            .sheet(item: $safetyAction) { action in
                NanaPostSafetySheet(context: contentStore.discussion(for: conversation), initialAction: action) { dismiss() }
            }
            .onChange(of: contentStore.safetyDismissalID) { _, _ in
                if !contentStore.visibleConversations.contains(where: { $0.id == conversation.id }) { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var messageHistory: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    profileCard
                    if messages.isEmpty {
                        Text("No messages yet")
                            .font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                            .padding(.vertical, 36)
                    }
                    ForEach(messages) { message in
                        messageBubble(message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("latest-message")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, _ in reader.scrollTo("latest-message", anchor: .bottom) }
            .onChange(of: composerFocused) { _, focused in
                if focused { reader.scrollTo("latest-message", anchor: .bottom) }
            }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingProfile = profile != nil } label: {
                HStack(spacing: 10) {
                    NanaAvatarView(title: conversation.displayName, assetKey: profile?.avatarAssetKey ?? conversation.avatarAssetKey, size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(conversation.displayName).font(.system(size: 16, weight: .medium)).lineLimit(1)
                            if contentStore.liveFriendRooms.contains(where: { $0.hostID == conversation.profileID }) {
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                                    .frame(width: 30, height: 12)
                            }
                        }
                        if let profile {
                            HStack(spacing: 7) {
                                Text("Lv.\(profile.level)")
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(NanaPalette.violet, in: Capsule())
                                Text("\(profile.age) · \(profile.region)")
                                    .foregroundStyle(NanaPalette.mutedWhite)
                            }.font(.system(size: 11))
                        }
                    }
                    Spacer(minLength: 0)
                    if profile != nil {
                        Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.yellow).frame(width: 30, height: 30)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .foregroundStyle(NanaPalette.warmWhite)
            }
            .buttonStyle(.plain)
            .disabled(profile == nil)
            if let profile {
                HStack(spacing: 10) {
                    profileStat("Fans", value: "\(profile.followerCount)", color: .green)
                    profileStat("Friends", value: "—", color: .cyan)
                    profileStat("Follow", value: "\(profile.followingCount)", color: .orange)
                }
                if !profile.introduction.isEmpty {
                    Text(profile.introduction).font(.system(size: 13))
                        .foregroundStyle(NanaPalette.mutedWhite).lineLimit(3)
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 14))
    }

    private func profileStat(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            Text(title).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func messageBubble(_ message: NanaMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isFromCurrentUser { Spacer(minLength: 36) }
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                Text(message.body)
                    .font(.system(size: 14))
                    .foregroundStyle(NanaPalette.warmWhite)
                    .padding(.horizontal, 15).padding(.vertical, 13)
                    .background(message.isFromCurrentUser ? NanaPalette.violet : Color(white: 0.29),
                                in: UnevenRoundedRectangle(topLeadingRadius: message.isFromCurrentUser ? 18 : 4,
                                                           bottomLeadingRadius: 18, bottomTrailingRadius: 18,
                                                           topTrailingRadius: message.isFromCurrentUser ? 4 : 18))
                Text(message.sentAtLabel)
                    .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
            }
            if !message.isFromCurrentUser { Spacer(minLength: 36) }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { showingEmoji.toggle(); showingAccessories = true } label: {
                    Image(systemName: "face.smiling").font(.system(size: 19))
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Emoji")
                TextField("Please enter", text: $draft, axis: .vertical)
                    .font(.system(size: 14)).lineLimit(1...4)
                    .focused($composerFocused)
                Button {
                    if hasDraft {
                        // Keep the draft when delivery is unavailable or fails.
                        _ = contentStore.saveDraft(draft, for: draftKey)
                        contentStore.appendMessage(to: conversation.id, body: draft)
                    } else {
                        showingAccessories.toggle()
                        composerFocused = false
                    }
                } label: {
                    Image(systemName: hasDraft ? "paperplane.fill" : "ellipsis")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 48, height: 32)
                        .background(NanaPalette.violet, in: Capsule())
                        .frame(width: 52, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasDraft ? "Send message" : "More actions")
            }
            .foregroundStyle(NanaPalette.warmWhite)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 27))
            if showingAccessories {
                if showingEmoji {
                    HStack {
                        ForEach(["😊", "❤️", "👏", "🎵", "✨", "👋"], id: \.self) { emoji in
                            Button { draft += emoji } label: {
                                Text(emoji).font(.system(size: 25)).frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    accessory("photo", label: "Photo") { contentStore.explainUnavailable("Sending photos in messages") }
                    accessory("face.smiling", label: "Emoji") { showingEmoji.toggle() }
                    accessory("phone.fill", label: "Call") { composerFocused = false; showingCall = true }
                    accessory("gift", label: "Gift") { contentStore.explainUnavailable("Sending gifts in private messages") }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.black.opacity(0.94))
    }

    private func accessory(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22))
                .foregroundStyle(symbol == "phone.fill" ? NanaPalette.neonPink : NanaPalette.warmWhite)
                .frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var conversationOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conversation options").font(.system(size: 22, weight: .bold))
            NanaPostSafetyButtons(subject: "conversation") { action in
                pendingSafetyAction = action
                showingMore = false
            }
            Button { showingMore = false } label: {
                Text("Cancel").frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white.opacity(0.09), in: Capsule())
            }.buttonStyle(.plain)
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(24)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color(red: 0.075, green: 0.055, blue: 0.105))
    }
}

struct NanaVideoCallView: View {
    let profile: NanaProfile

    var body: some View {
        NanaUnavailableSurface(title: "Video calls are unavailable", detail: "The published A-side contract does not include a call transport yet.")
    }
}

private struct NanaUnavailableSurface: View {
    let title: String
    let detail: String
    var body: some View {
        ZStack {
            NanaBackdrop()
            NanaEmptyState(title: title, detail: detail, actionTitle: nil, action: nil)
                .padding(22)
        }
        .preferredColorScheme(.dark)
    }
}
