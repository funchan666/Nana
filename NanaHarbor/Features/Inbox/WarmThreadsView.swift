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

    private var visibleConversations: [NanaConversation] {
        contentStore.visibleConversations
    }

    private var friendProfiles: [NanaProfile] {
        Array(contentStore.payload.profiles.filter { !contentStore.blockedProfileIDs.contains($0.id) }.prefix(6))
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
                        VStack(alignment: .leading, spacing: 17) {
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
            .sheet(isPresented: $showingRanking) { NanaUnavailableSurface(title: "Ranking is unavailable", detail: "The published A-side service does not include ranking data yet.") }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
        }
    }

    private var messagesHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Messages")
                .font(.system(size: 20, weight: .bold, design: .serif).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            Spacer()
            Button { showingNoticeCenter = true } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NanaPalette.warmWhite)
                    .frame(width: 33, height: 32)
                    .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { contentStore.clearConversationList() } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NanaPalette.softPink)
                    .frame(width: 33, height: 32)
                    .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
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
            VStack(spacing: 7) {
                NanaAssetImage(assetKey: assetKey, contentMode: .fit)
                    .frame(width: 58, height: 42)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NanaPalette.warmWhite)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var friendRoom: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Friend Room")
                    .font(.system(size: 14, weight: .bold, design: .serif).italic())
                    .foregroundStyle(NanaPalette.warmWhite)
                Spacer()
                Button("View all") { showingFriends = true }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(NanaPalette.electricLilac)
            }
            if friendProfiles.isEmpty {
                Text("Your friend room is waiting for its first hello.")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(friendProfiles) { profile in
                            Button { selectedProfile = profile } label: {
                                VStack(spacing: 5) {
                                    ZStack(alignment: .bottomTrailing) {
                                        NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 53)
                                        Circle().fill(Color.green).frame(width: 10, height: 10).overlay(Circle().stroke(NanaPalette.midnight, lineWidth: 2))
                                    }
                                    Text(profile.displayName.split(separator: " ").first.map(String.init) ?? profile.displayName)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(NanaPalette.mutedWhite)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var chatList: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Chat List")
                .font(.system(size: 14, weight: .bold, design: .serif).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            if visibleConversations.isEmpty {
                NanaEmptyState(title: "No messages yet", detail: "A good room is a good place to start.", actionTitle: nil, action: nil)
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleConversations) { conversation in
                        Button { selectedConversation = conversation } label: { conversationRow(conversation) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func conversationRow(_ conversation: NanaConversation) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                NanaAvatarView(title: conversation.displayName, assetKey: conversation.avatarAssetKey, size: 49)
                Circle().fill(Color.green).frame(width: 9, height: 9).overlay(Circle().stroke(NanaPalette.cardStrong, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(NanaPalette.warmWhite)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(NanaPalette.warning, in: Circle())
                    }
                }
                Text(conversation.preview)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(1)
            }
            Spacer()
            Text(conversation.sentAtLabel)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(NanaPalette.mutedWhite)
        }
        .padding(12)
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    let profile: NanaProfile
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
                        Text("2005/10/25  23:13:25").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(albumAssets, id: \.self) { asset in
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
            .navigationTitle(profile.displayName)
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
