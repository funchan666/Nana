import SwiftUI
import PhotosUI
import UIKit

struct WarmThreadsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedConversation: NanaConversation?
    @State private var selectedProfile: NanaProfile?
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

    private var friendProfiles: [NanaProfile] {
        contentStore.payload.profiles.filter { !contentStore.blockedProfileIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                if contentStore.payload.conversations.isEmpty && contentStore.state(for: .conversations) == .loading {
                    NanaScreenLoading(label: "Warming messages")
                } else if contentStore.payload.conversations.isEmpty, case .failed(let error) = contentStore.state(for: .conversations) {
                    NanaErrorState(title: "Messages are unavailable", detail: error.localizedDescription, actionTitle: "Retry") {
                        Task { await contentStore.refresh(.conversations) }
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
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
                    .refreshable { await contentStore.refresh(.conversations) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await contentStore.refresh(.conversations) }
            .sheet(item: $selectedConversation) { conversation in NanaConversationView(conversation: conversation) }
            .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
            .sheet(isPresented: $showingNoticeCenter) { NanaNotificationCenterView() }
            .sheet(isPresented: $showingFriends) { NanaFriendsListView() }
            .fullScreenCover(isPresented: $showingRanking) { NanaRankingView() }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
            .sheet(isPresented: $showingAlbum) { NanaAlbumGalleryView() }
            .confirmationDialog("Clear this device's chat list?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("Clear chat list", role: .destructive) { contentStore.clearConversationList() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This only hides conversations on this device. Messages on the service are not deleted.")
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
        contentStore.payload.rooms.contains { room in
            room.hostID == profileID
                && room.streamSourceType != "simulatedReplay"
                && ["live", "live now"].contains(room.roomState.lowercased())
        }
    }

    private var friendRoom: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Friend Room")
                .font(.system(size: 13, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            if friendProfiles.isEmpty {
                Text("Your friend room is waiting for its first hello.")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 17) {
                        ForEach(friendProfiles) { profile in
                            Button { selectedProfile = profile } label: {
                                VStack(spacing: 7) {
                                    NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 57)
                                        .overlay(Circle().stroke(NanaPalette.softPink, lineWidth: 1.5))
                                        .overlay(alignment: .bottom) {
                                            if hasLiveRoom(profileID: profile.id) {
                                                NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                                                    .frame(width: 32, height: 11)
                                                    .offset(y: 2)
                                            }
                                        }
                                    Text(profile.displayName.split(separator: " ").first.map(String.init) ?? profile.displayName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(NanaPalette.warmWhite)
                                        .lineLimit(1)
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.plain)
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
                NanaEmptyState(title: "No messages yet", detail: "A good room is a good place to start.", actionTitle: nil, action: nil)
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

struct NanaNotificationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingDetail = false
    private let notices = [
        ("Platform Notification", "The community guidance has been updated.", "02:11"),
        ("Platform Notification", "Please keep rooms welcoming and respectful.", "Yesterday")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(notices.enumerated()), id: \.offset) { notice in
                            Button { showingDetail = true } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(notice.element.0).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                                        Spacer()
                                        Text(notice.element.2).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                                    }
                                    Text(notice.element.1).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                                }
                                .padding(15)
                                .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("System Notification")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(isPresented: $showingDetail) { NanaNotificationDetailView() }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaNotificationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Platform Notification").font(NanaType.section).foregroundStyle(NanaPalette.warmWhite)
                        Text("Community reminders help maintain respect for rooms and messages. When you see harassment, impersonation, spam, unsafe requests, or other policy violations, please use Report or Block from the relevant profile. Keep personal information private and leave conversations that no longer feel comfortable.")
                            .font(NanaType.body)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineSpacing(5)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Notification details")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaFriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedProfile: NanaProfile?
    @State private var selectedConversation: NanaConversation?
    @State private var showingNew = false
    @State private var callProfile: NanaProfile?

    private var profiles: [NanaProfile] {
        contentStore.payload.profiles.filter { !contentStore.blockedProfileIDs.contains($0.id) }
    }

    private var visibleProfiles: [NanaProfile] {
        showingNew ? profiles.filter { !$0.isConnected } : profiles
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 13) {
                        HStack(spacing: 8) {
                            friendStat("Friend", "\(profiles.count)")
                            friendStat("Call duration", "45:45:12")
                            friendStat("Missed", "256")
                        }
                        HStack(spacing: 24) {
                            friendTab("Friends", isSelected: !showingNew) { showingNew = false }
                            friendTab("New", isSelected: showingNew) { showingNew = true }
                            Spacer()
                        }
                        if visibleProfiles.isEmpty {
                            NanaEmptyState(
                                title: showingNew ? "No new friends" : "No friends yet",
                                detail: "Your circle will appear here when there is something to show.",
                                actionTitle: nil,
                                action: nil
                            )
                        } else {
                            ForEach(visibleProfiles) { profile in
                                friendRow(profile)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Friends")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
            .sheet(item: $callProfile) { profile in NanaVideoCallView(profile: profile) }
            .sheet(item: $selectedConversation) { conversation in NanaConversationView(conversation: conversation) }
        }
        .preferredColorScheme(.dark)
    }

    private func friendStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(NanaPalette.softPink)
            Text(title).font(.system(size: 9, design: .rounded)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func friendTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(title).font(.system(size: 13, weight: .bold, design: .serif).italic()).foregroundStyle(isSelected ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
                Capsule().fill(isSelected ? NanaPalette.neonPink : .clear).frame(width: 28, height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func friendRow(_ profile: NanaProfile) -> some View {
        HStack(spacing: 10) {
            Button { selectedProfile = profile } label: { NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 50) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(NanaPalette.warmWhite)
                Text("\(profile.region) · Lv.\(profile.level)").font(.system(size: 10, design: .rounded)).foregroundStyle(NanaPalette.mutedWhite)
                Text(profile.isConnected ? "Call completed" : "No answer").font(.system(size: 9, design: .rounded)).foregroundStyle(profile.isConnected ? Color.green : NanaPalette.softPink)
            }
            Spacer()
            Button { callProfile = profile } label: { Image(systemName: "video.fill").foregroundStyle(.white).frame(width: 32, height: 32).background(NanaPalette.violet, in: Circle()) }.buttonStyle(.plain)
            Button {
                selectedConversation = contentStore.visibleConversations.first { $0.profileID == profile.id }
            } label: {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(NanaPalette.neonPink, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct NanaAlbumGalleryView: View {
    var profile: NanaProfile? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var isSelecting = false
    @State private var selectedAssets: Set<String> = []
    @State private var selectedPhoto: PhotosPickerItem?
    private let albumAssets = ["nana.pic.Dc0SA4UiUy3", "nana.pic.Dc1CvDfCCHN", "nana.pic.Dc1Ii5HACCq", "nana.pic.Dc1UKGTDL1J", "nana.pic.DdTmQsaCOiK", "nana.pic.DdV5vxnEs3N"]

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Personal Album").font(.system(size: 20, weight: .bold, design: .serif).italic()).foregroundStyle(NanaPalette.warmWhite)
                        Text("All the shared moments are here.").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        if profile == nil && contentStore.personal.photos.isEmpty {
                            Text("Your album is empty. Upload a photo to keep it on this device.")
                                .font(NanaType.body)
                                .foregroundStyle(NanaPalette.mutedWhite)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 24)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(profile == nil ? [] : albumAssets, id: \.self) { asset in
                                Button {
                                    guard isSelecting else { return }
                                    if selectedAssets.contains(asset) { selectedAssets.remove(asset) }
                                    else { selectedAssets.insert(asset) }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        NanaAssetImage(assetKey: asset)
                                            .frame(height: 102)
                                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                        if isSelecting {
                                            Image(systemName: selectedAssets.contains(asset) ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(selectedAssets.contains(asset) ? NanaPalette.softPink : .white)
                                                .shadow(color: .black.opacity(0.6), radius: 3)
                                                .padding(7)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(contentStore.personal.photos) { photo in
                                Button {
                                    guard isSelecting else { return }
                                    if selectedAssets.contains(photo.id) { selectedAssets.remove(photo.id) }
                                    else { selectedAssets.insert(photo.id) }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        NanaPersonalPhotoImage(url: contentStore.photoURL(photo))
                                            .frame(height: 102)
                                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                        if isSelecting {
                                            Image(systemName: selectedAssets.contains(photo.id) ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(selectedAssets.contains(photo.id) ? NanaPalette.softPink : .white)
                                                .shadow(color: .black.opacity(0.6), radius: 3)
                                                .padding(7)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if isSelecting {
                            HStack(spacing: 10) {
                                Text("\(selectedAssets.count) selected")
                                    .font(NanaType.caption)
                                    .foregroundStyle(NanaPalette.mutedWhite)
                                Spacer()
                                Button("Delete selected") {
                                    let localIDs = Set(selectedAssets.filter { id in contentStore.personal.photos.contains(where: { $0.id == id }) })
                                    contentStore.deletePhotos(localIDs)
                                    selectedAssets.subtract(localIDs)
                                }
                                    .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
                                    .disabled(selectedAssets.isEmpty)
                                    .opacity(selectedAssets.isEmpty ? 0.45 : 1)
                            }
                        } else {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text("Upload photo").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NanaPrimaryButtonStyle())
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(profile?.displayName ?? "Personal Album")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Done" : "Choice") {
                        isSelecting.toggle()
                        if !isSelecting { selectedAssets.removeAll() }
                    }
                    .foregroundStyle(NanaPalette.electricLilac)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        contentStore.addPhoto(data, accountID: contentStore.accountScope)
                    }
                    selectedPhoto = nil
                }
            }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaPersonalPhotoImage: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
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
    @State private var showingCall = false

    private var messages: [NanaMessage] {
        contentStore.payload.messages.filter { $0.conversationID == conversation.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 13) {
                            NanaAvatarView(title: conversation.displayName, assetKey: conversation.avatarAssetKey, size: 72)
                            Text(conversation.displayName)
                                .font(NanaType.section)
                                .foregroundStyle(NanaPalette.warmWhite)
                            Text("A private conversation")
                                .font(NanaType.caption)
                                .foregroundStyle(NanaPalette.mutedWhite)
                            ForEach(messages) { message in
                                HStack {
                                    if message.isFromCurrentUser { Spacer(minLength: 60) }
                                    Text(message.body)
                                        .font(NanaType.body)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .background(message.isFromCurrentUser ? NanaPalette.violet : NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    if !message.isFromCurrentUser { Spacer(minLength: 60) }
                                }
                            }
                        }
                        .padding(20)
                    }
                    HStack(spacing: 8) {
                        TextField("Write a message…", text: $draft)
                            .foregroundStyle(.white)
                            .nanaGlassField()
                        Button {
                            contentStore.appendMessage(to: conversation.id, body: draft)
                            draft = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(NanaPalette.violet, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(NanaPalette.deepSpace.opacity(0.96))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCall = true } label: { Image(systemName: "video.fill").foregroundStyle(NanaPalette.neonPink) }
                }
            }
            .task {
                contentStore.markRead(conversation)
                if conversation.id == "conversation-ava" { await contentStore.refresh(.avaMessages) }
            }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
            .sheet(isPresented: $showingCall) {
                if let profile = contentStore.profile(with: conversation.profileID) { NanaVideoCallView(profile: profile) }
                else { NanaUnavailableSurface(title: "Video calls are not available", detail: "This profile is not in the current A-side snapshot.") }
            }
        }
        .preferredColorScheme(.dark)
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
