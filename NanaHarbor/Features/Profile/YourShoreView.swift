import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import UserNotifications

struct YourShoreView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var showingEdit = false
    @State private var showingWallet = false
    @State private var showingCheckIn = false
    @State private var collectionDestination: NanaCollectionDestination?
    @State private var showingLevel = false
    @State private var showingFeedback = false
    @State private var showingConnections = false
    @State private var connectionCategory = "Friends"
    @State private var showingSettings = false
    @State private var showingBlacklist = false
    @State private var showingLogout = false

    private var localProfile: NanaProfile {
        NanaProfile(id: "profile-self", displayName: sessionStore.activeProfile?.displayName ?? "Nana member", handle: "nana.member", region: sessionStore.activeProfile?.country ?? "Not set", language: "Not set", gender: sessionStore.activeProfile?.gender ?? "Not set", age: Calendar.current.dateComponents([.year], from: sessionStore.activeProfile?.birthDate ?? Date(), to: Date()).year ?? 0, introduction: "Shape your profile with the places, people and moments you want to keep close.", avatarAssetKey: nil, isConnected: false, followerCount: 0, followingCount: 0, level: contentStore.activityLevel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                if contentStore.state(for: .wallet) == .loading && contentStore.payload.wallet.nextLevelPoints == 1 {
                    NanaScreenLoading(label: "Loading your shore")
                } else if case .failed(let error) = contentStore.state(for: .wallet), contentStore.payload.wallet.nextLevelPoints == 1 {
                    NanaErrorState(title: "Your profile is unavailable", detail: error.localizedDescription, actionTitle: "Retry") { Task { await contentStore.refresh(.wallet) } }
                } else { ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        profileCard
                        statsRow
                        checkInCard
                        balanceStrip
                        profileMenu
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 90)
                } }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await contentStore.refresh(.wallet)
                coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
            }
            .fullScreenCover(isPresented: $showingEdit) { NanaEditProfileView() }
            .fullScreenCover(isPresented: $showingWallet) { NanaWalletView() }
            .fullScreenCover(isPresented: $showingCheckIn) { NanaCheckInView() }
            .fullScreenCover(item: $collectionDestination) { NanaCollectionView(destination: $0) }
            .fullScreenCover(isPresented: $showingLevel) { NanaLevelView() }
            .fullScreenCover(isPresented: $showingFeedback) { NanaFeedbackView() }
            .fullScreenCover(isPresented: $showingConnections) { NanaConnectionsView(profile: localProfile, initialTab: connectionCategory) }
            .fullScreenCover(isPresented: $showingSettings) { NanaSettingsView() }
            .fullScreenCover(isPresented: $showingBlacklist) { NanaBlacklistView() }
            .sheet(isPresented: $showingLogout) {
                NanaProfileActionSheet(title: "Log out?", detail: "Your saved profile and photos will be here when you sign in again.", actionTitle: "Confirm exit",
                                       secondaryTitle: "Switch accounts", secondaryAction: { sessionStore.signOut() }) {
                    Task { await sessionStore.exitAccount(deleting: false, contentStore: contentStore, coinStore: coinStore) }
                }
            }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
            .overlay { if let progress = sessionStore.accountExitProgress { NanaAccountExitOverlay(progress: progress) } }
        }
    }

    private var header: some View {
        Text("My Profile")
            .font(.system(size: 19, weight: .heavy).italic())
            .foregroundStyle(NanaPalette.warmWhite)
            .frame(height: 36, alignment: .leading)
    }

    private var profileCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Button { showingEdit = true } label: {
                NanaAccountAvatarView(data: sessionStore.activeProfile?.avatarData, size: 72)
                .padding(3)
                .overlay(Circle().stroke(NanaPalette.violet, lineWidth: 1.5))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, NanaPalette.electricLilac)
                        .background(.white, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(localProfile.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NanaPalette.warmWhite)
                        .lineLimit(1)
                    Text("Lv.\(localProfile.level)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(colors: [Color.orange, NanaPalette.softPink, NanaPalette.violet, Color.cyan], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                        .fixedSize()
                }
                HStack(spacing: 7) {
                    if sessionStore.activeProfile?.birthDate != nil {
                        Text("\(localProfile.age)")
                    }
                    Text(localProfile.region.isEmpty ? "Not set" : localProfile.region)
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(NanaPalette.mutedWhite)
                Text(profileInterests)
                    .font(.system(size: 11))
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 7)

            Button { showingSettings = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_168", contentMode: .fit)
                    .frame(width: 29, height: 29)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .padding(.top, 3)
        }
    }

    private var profileInterests: String {
        if let signature = sessionStore.activeProfile?.introduction, !signature.isEmpty { return signature }
        let interests = sessionStore.activeProfile?.interests ?? []
        return interests.isEmpty ? "Add your interests to make this space yours." : interests.joined(separator: " · ")
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("Follower", value: "\(contentStore.accountFollowers.count)", category: "Followers")
            stat("Following", value: "\(contentStore.followedProfiles.count)", category: "Following")
            stat("Friends", value: "\(contentStore.mutualFriends.count)", category: "Friends")
            Spacer(minLength: 0)
        }
        .padding(.top, 5)
    }

    private func stat(_ title: String, value: String, category: String) -> some View {
        Button {
            connectionCategory = category
            showingConnections = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(NanaPalette.warmWhite)
                Text(title).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
            }
            .frame(width: 82, height: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("「 Sign in today 」")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NanaPalette.warmWhite)
                Spacer()
                Button { showingCheckIn = true } label: {
                    Group {
                        if contentStore.checkedInToday {
                            Text("Checked in")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 89, height: 25)
                                .background(NanaPalette.violet, in: Capsule())
                        } else {
                            NanaAssetImage(assetKey: "nana.voice.voice_asset_146", contentMode: .fit)
                                .frame(width: 89, height: 25)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(contentStore.checkedInToday ? "View check-in calendar" : "Check in")
            }
            HStack(spacing: 10) {
                ForEach(0..<10, id: \.self) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index - 9, to: Date()) ?? Date()
                    let checked = contentStore.personal.checkInDays.contains(contentStore.dayKey(date))
                    Circle()
                        .fill(checked ? NanaPalette.violet : Color.white.opacity(0.24))
                        .frame(width: 9, height: 9)
                        .overlay {
                            if index == 9 && checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(contentStore.personal.checkInDays.count) check-ins recorded")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 20) {
                    Text("Lv\(contentStore.activityLevel)")
                        .foregroundStyle(NanaPalette.warmWhite)
                    HStack(spacing: 0) {
                        Text("\(contentStore.activityPoints % 200)").foregroundStyle(NanaPalette.electricLilac)
                        Text("/200").foregroundStyle(NanaPalette.mutedWhite)
                    }
                }
                .font(.system(size: 11))
                GeometryReader { geometry in
                    let width = geometry.size.width * CGFloat(contentStore.activityPoints % 200) / 200
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.85))
                        Capsule().fill(NanaPalette.violet).frame(width: width)
                        Circle().fill(NanaPalette.violet)
                            .frame(width: 7, height: 7)
                            .offset(x: max(0, min(width - 3.5, geometry.size.width - 7)))
                    }
                }
                .frame(height: 4)
                .accessibilityLabel("Activity progress, \(contentStore.activityPoints % 200) of 200 points")
            }
            .padding(.top, 3)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color(red: 0.39, green: 0.34, blue: 0.61).opacity(0.7), NanaPalette.deepSpace.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 0.7))
    }

    private var balanceStrip: some View {
        Button { showingWallet = true } label: {
            HStack(spacing: 8) {
                // The original strip already contains the coin artwork on its left edge.
                Color.clear.frame(width: 43, height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("My balance").font(.system(size: 13, weight: .medium))
                    Text(contentStore.preference("hideCoinBalance", default: false) ? "••••" : coinStore.balance.formatted()).font(.system(size: 11))
                }
                .foregroundStyle(NanaPalette.warmWhite)
                Spacer(minLength: 3)
                NanaAssetImage(assetKey: "nana.voice.voice_asset_106", contentMode: .fit)
                    .frame(width: 53, height: 26)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background {
                GeometryReader { geometry in
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_105")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contentStore.preference("hideCoinBalance", default: false) ? "Balance hidden. Open wallet" : "My balance, \(coinStore.balance) coins. Open wallet")
    }

    private var profileMenu: some View {
        VStack(spacing: 8) {
            menuRow(title: "Shop", icon: "storefront.fill") { collectionDestination = .store }
            menuRow(title: "Backpack", icon: "backpack.fill") { collectionDestination = .backpack }
            menuRow(title: "My level", icon: "diamond.fill") { showingLevel = true }
            menuRow(title: "Feedback", icon: "questionmark.bubble.fill") { showingFeedback = true }
            menuRow(title: "Blacklist", icon: "person.crop.circle.badge.xmark") { showingBlacklist = true }
            menuRow(title: "Log out", icon: "power", destructive: true) { showingLogout = true }
        }
    }

    private func menuRow(title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if destructive {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_023", contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NanaPalette.warmWhite)
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                Spacer()
                NanaAssetImage(assetKey: "nana.voice.voice_asset_033", contentMode: .fit)
                    .frame(width: 14, height: 20)
                    .opacity(0.9)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(NanaProfileMenuButtonStyle())
    }

}

private struct NanaProfileMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? NanaPalette.violet.opacity(0.3) : Color(white: 0.14),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.3 : 0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NanaUserProfileView: View {
    let profile: NanaProfile
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingCall = false
    @State private var safetyAction: NanaPostSafetyAction?
    @State private var conversation: NanaConversation?
    @State private var selectedVideo: NanaBundledVideo?
    @State private var selectedPost: NanaPost?
    @State private var selectedRoom: NanaLiveRoom?
    @State private var photoSelection: NanaPublicPhotoSelection?
    @State private var showsAlbum = false

    private var liveProfile: NanaProfile { contentStore.profile(with: profile.id) ?? profile }
    private var following: Bool { contentStore.isFollowing(profile.id) }
    private var videos: [NanaBundledVideo] {
        NanaAssetLibrary.videoClips.filter {
            contentStore.discussion(for: $0).authorID == profile.id && contentStore.isVideoVisible($0)
        }
    }
    private var posts: [NanaPost] {
        contentStore.posts().filter { $0.authorID == profile.id && $0.coverAssetKey?.hasPrefix("nana.video.") != true }
    }
    private var photos: [String] {
        var seen = Set<String>()
        let publishedPhotos = (liveProfile.publicPhotoAssetKeys ?? []) + posts.compactMap(\.coverAssetKey)
        return publishedPhotos.filter {
            !$0.hasPrefix("nana.video.") && NanaAssetLibrary.image(for: $0) != nil && seen.insert($0).inserted
        }
    }
    private var cover: String? { liveProfile.avatarAssetKey ?? photos.first }
    private var room: NanaLiveRoom? {
        let visible = contentStore.payload.rooms.filter { contentStore.isRoomVisible($0) }
        return visible.first { $0.hostID == profile.id } ?? visible.first
    }
    private var interests: [String] {
        var categories = posts.map(\.category)
        if let room, room.hostID == profile.id { categories.insert(room.category, at: 0) }
        if categories.isEmpty && !videos.isEmpty { categories = ["Video creator"] }
        var seen = Set<String>()
        return Array(categories.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(3))
    }
    private var metadata: String {
        [liveProfile.age > 0 ? String(liveProfile.age) : nil,
         liveProfile.region.isEmpty ? nil : liveProfile.region,
         liveProfile.level > 0 ? "Lv.\(liveProfile.level)" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero(width: geometry.size.width, height: max(440, min(570, geometry.size.width * 1.34)))
                        VStack(alignment: .leading, spacing: 12) {
                            if let room { roomCard(room) }
                            contentTabs.zIndex(1)
                            if showsAlbum { albumGrid } else { postGrid }
                        }
                        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 100)
                    }
                }
                .ignoresSafeArea(edges: .top)
                HStack {
                    Button { dismiss() } label: {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_030", contentMode: .fit)
                            .frame(width: 25, height: 25).frame(width: 44, height: 44)
                    }.accessibilityLabel("Back")
                    Spacer()
                    Button { safetyAction = .options } label: {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_119", contentMode: .fit)
                            .frame(width: 27, height: 27).frame(width: 44, height: 44)
                    }.accessibilityLabel("More profile options")
                }
                .buttonStyle(.plain).padding(.horizontal, 12)
            }
            .overlay(alignment: .bottom) { contactActions }
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCall) { NanaVideoCallView(profile: liveProfile) }
        .fullScreenCover(item: $conversation) { NanaConversationView(conversation: $0, recipientProfile: liveProfile) }
        .fullScreenCover(item: $selectedVideo) { NanaVideoPlayerView(clip: $0) }
        .fullScreenCover(item: $selectedPost) { NanaPostDetailView(post: $0) }
        .fullScreenCover(item: $selectedRoom) { NanaLiveRoomView(room: $0) }
        .fullScreenCover(item: $photoSelection) { NanaPublicPhotoViewer(profile: liveProfile, selection: $0) }
        .sheet(item: $safetyAction) { action in
            NanaPostSafetySheet(context: contentStore.discussion(for: liveProfile), initialAction: action) { dismiss() }
        }
        .onChange(of: contentStore.safetyDismissalID) { _, _ in
            if contentStore.hiddenAuthorIDs.contains(profile.id) { dismiss() }
        }
        .task { if profile.id == "profile-ava" { await contentStore.refresh(.avaProfile) } }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                if let cover { photoSelection = NanaPublicPhotoSelection(assets: [cover] + photos.filter { $0 != cover }, index: 0) }
            } label: {
                Group {
                    if let cover { NanaAssetImage(assetKey: cover) }
                    else { NanaAvatarView(title: liveProfile.displayName, assetKey: nil, size: 140) }
                }
                .frame(width: width, height: height).clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("View \(liveProfile.displayName)'s photo")
            LinearGradient(stops: [.init(color: .clear, location: 0.48), .init(color: .black.opacity(0.28), location: 0.68), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(liveProfile.displayName).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                        if !metadata.isEmpty { Text(metadata).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    NanaProfileArtworkButton(asset: following ? "101" : "100", label: following ? "Unfollow" : "Follow", height: 32) {
                        contentStore.toggleConnection(for: liveProfile)
                    }.frame(width: 92)
                }
                if liveProfile.hasCompleteDetails != false {
                    HStack(spacing: 20) {
                        Text("\(liveProfile.followerCount) Follower")
                        Text("\(liveProfile.followingCount) Following")
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(NanaPalette.mutedWhite)
                }
                if !interests.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { ForEach(interests, id: \.self) { interestTag($0) } }
                        interestTag(interests[0])
                    }
                }
                if !liveProfile.introduction.isEmpty {
                    Text(liveProfile.introduction).font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if contentStore.isWelcomeFollower(profile.id) {
                    Text("Welcome interaction · simulated locally").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                }
            }.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .frame(width: width, height: height)
    }

    private func interestTag(_ title: String) -> some View {
        Text("# " + title).font(.system(size: 11, weight: .medium))
            .foregroundStyle(NanaPalette.electricLilac)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(NanaPalette.electricLilac.opacity(0.7), lineWidth: 0.7))
    }

    private func roomCard(_ room: NanaLiveRoom) -> some View {
        Button { selectedRoom = room } label: {
            HStack(spacing: 10) {
                NanaAssetImage(assetKey: room.hostAvatarAssetKey ?? NanaAccountAvatarView.defaultAssetKey)
                    .frame(width: 72, height: 94).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(room.hostName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(room.streamSourceType == "simulatedReplay" ? "Replay" : room.roomState)
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(NanaPalette.neonPink)
                    }
                    Text(room.hostID == profile.id ? "Hosted room" : "Recommended room")
                        .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
                    interestTag(room.category)
                    HStack(spacing: 6) {
                        Text(room.title).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                        Spacer(minLength: 0)
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_033", contentMode: .fit).frame(width: 8, height: 12)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(8)
                .background { NanaAssetImage(assetKey: "nana.voice.voice_asset_042").allowsHitTesting(false) }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private var contentTabs: some View {
        HStack(spacing: 28) {
            tab("Posts", selected: !showsAlbum) { showsAlbum = false }
            tab("Photo album", selected: showsAlbum) { showsAlbum = true }
        }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .heavy).italic())
                .foregroundStyle(selected ? .white : NanaPalette.mutedWhite)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    if selected { Image("NanaCheckInGuideButton").resizable().frame(width: 28, height: 3).allowsHitTesting(false).accessibilityHidden(true) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var postGrid: some View {
        if videos.isEmpty && posts.isEmpty { emptyContent("No posts yet", detail: "Shared posts will appear here.") }
        LazyVStack(spacing: 12) {
            ForEach(videos) { video in
                Button { selectedVideo = video } label: {
                    NanaMediaPreview(assetKey: video.assetKey).frame(height: 260).clipped()
                        .overlay(alignment: .bottomTrailing) {
                            NanaAssetImage(assetKey: "nana.voice.voice_asset_011", contentMode: .fit)
                                .frame(width: 30, height: 30).padding(10).allowsHitTesting(false)
                        }.clipShape(RoundedRectangle(cornerRadius: 13))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain).accessibilityLabel("Play video by \(liveProfile.displayName)")
            }
        }
        ForEach(posts) { post in
            VStack(alignment: .leading, spacing: 10) {
                if let asset = post.coverAssetKey, NanaAssetLibrary.image(for: asset) != nil {
                    Button { openPhoto(asset) } label: {
                        NanaMediaPreview(assetKey: asset).frame(height: 260).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityLabel("View photo by \(liveProfile.displayName)")
                }
                Button { selectedPost = post } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.title).font(.system(size: 16, weight: .semibold))
                        Text(post.body).font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Read the post and its comments")
            }
        }
    }

    private func openPhoto(_ asset: String) {
        let album = photos.contains(asset) ? photos : [asset] + photos
        photoSelection = NanaPublicPhotoSelection(assets: album, index: album.firstIndex(of: asset) ?? 0)
    }

    @ViewBuilder private var albumGrid: some View {
        if photos.isEmpty { emptyContent("No shared photos yet", detail: "This person's public photos will appear here.") }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(photos.enumerated()), id: \.element) { index, asset in
                Button { photoSelection = NanaPublicPhotoSelection(assets: photos, index: index) } label: {
                    NanaMediaPreview(assetKey: asset).frame(height: 220).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain).accessibilityLabel("View photo \(index + 1)")
            }
        }
    }

    private func emptyContent(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
        }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
    }

    private var contactActions: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.width - 12)
            let height = min(56, available * 114 / 674)
            HStack(spacing: 12) {
                NanaProfileArtworkButton(asset: "152", label: "Chat", height: height) {
                    conversation = contentStore.conversation(for: liveProfile)
                }.frame(width: available * 260 / 674)
                NanaProfileArtworkButton(asset: "145", label: "Start video", height: height) { showingCall = true }
                    .frame(width: available * 414 / 674)
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct NanaProfileArtworkButton: View {
    let asset: String
    let label: String
    var height: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_\(asset)", contentMode: .fit)
                .frame(height: height).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

private struct NanaPublicPhotoSelection: Identifiable {
    let id = UUID()
    let assets: [String]
    let index: Int
}

private struct NanaPublicPhotoViewer: View {
    let profile: NanaProfile
    let selection: NanaPublicPhotoSelection
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var index: Int
    @State private var safetyAction: NanaPostSafetyAction?

    init(profile: NanaProfile, selection: NanaPublicPhotoSelection) {
        self.profile = profile
        self.selection = selection
        _index = State(initialValue: min(max(0, selection.index), max(0, selection.assets.count - 1)))
    }
    private var following: Bool { contentStore.isFollowing(profile.id) }
    private var currentAsset: String? { selection.assets.indices.contains(index) ? selection.assets[index] : nil }
    private var likeKey: String { "profile-photo-like-\(profile.id)-\(currentAsset ?? "")" }
    private var isLiked: Bool { contentStore.preference(likeKey, default: false) }
    private var visiblePageIndices: Range<Int> {
        let start = max(0, min(index - 3, selection.assets.count - 7))
        return start..<min(selection.assets.count, start + 7)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                TabView(selection: $index) {
                    ForEach(Array(selection.assets.enumerated()), id: \.offset) { position, asset in
                        NanaMediaPreview(assetKey: asset)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped().tag(position)
                            .accessibilityLabel("Photo \(position + 1) of \(selection.assets.count)")
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
            }.ignoresSafeArea()
            LinearGradient(stops: [
                .init(color: .black.opacity(0.38), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.65),
                .init(color: .black.opacity(0.55), location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                photoToolbar
                Spacer()
                if selection.assets.count > 1 {
                    VStack(spacing: 10) {
                        Text("Swipe left or right to view photos").font(.system(size: 12))
                            .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                        HStack(spacing: 6) {
                            ForEach(visiblePageIndices, id: \.self) { page in
                                Image("NanaCheckInGuideButton").resizable()
                                    .frame(width: page == index ? 16 : 6, height: 6)
                                    .clipShape(Capsule()).opacity(page == index ? 1 : 0.4)
                            }
                        }.accessibilityHidden(true)
                    }.padding(.bottom, 24).allowsHitTesting(false)
                }
                photoActions
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white).preferredColorScheme(.dark)
        .sheet(item: $safetyAction) { action in
            NanaPostSafetySheet(context: contentStore.discussion(for: profile), initialAction: action) { dismiss() }
        }
        .onChange(of: contentStore.safetyDismissalID) { _, _ in
            if contentStore.hiddenAuthorIDs.contains(profile.id) { dismiss() }
        }
        .overlay {
            if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } }
        }
    }

    private var photoToolbar: some View {
        ZStack {
            Text("\(selection.assets.isEmpty ? 0 : index + 1)/\(selection.assets.count)")
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .accessibilityLabel("Photo \(selection.assets.isEmpty ? 0 : index + 1) of \(selection.assets.count)")
            HStack {
                Button { dismiss() } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_030", contentMode: .fit)
                        .frame(width: 26, height: 26).frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("Back")
                Spacer()
                Button { safetyAction = .options } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_119", contentMode: .fit)
                        .frame(width: 27, height: 27).frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("More profile options")
            }
        }.padding(.horizontal, 12).padding(.top, 4)
    }

    private var photoActions: some View {
        HStack(spacing: 12) {
            NanaProfileArtworkButton(asset: isLiked ? "167" : "098", label: isLiked ? "Unlike photo" : "Like photo", height: 50) {
                guard currentAsset != nil else { return }
                contentStore.setPreference(likeKey, value: !isLiked)
            }.frame(width: 94).disabled(currentAsset == nil)
            NanaProfileArtworkButton(asset: following ? "150" : "137", label: following ? "Unfollow" : "Follow", height: 50) {
                contentStore.toggleConnection(for: profile)
            }.frame(maxWidth: .infinity)
        }.frame(maxWidth: 360).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 28)
    }
}

private struct NanaEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var displayName = ""
    @State private var country = ""
    @State private var gender = ""
    @State private var birthDate: Date?
    @State private var selectedInterests = Set<String>()
    @State private var introduction = ""
    @State private var avatarData: Data?
    @State private var resetAvatar = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var editingAccountScope: String?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var showingDate = false
    @FocusState private var focusedField: ProfileField?
    private enum ProfileField: Hashable { case nickname, country, signature }
    private var canSave: Bool {
        editingAccountScope == sessionStore.activeProfile?.localAccountScope
            && editingAccountScope != nil && !loadingPhoto
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var interestOptions: [String] {
        Array(Set(["Music", "Live chat", "Creative", "Travel", "Gaming", "Late night", "Art", "Open talk"]
                  + (sessionStore.activeProfile?.interests ?? []) + Array(selectedInterests))).sorted()
    }
    private var choiceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        NanaProfilePage("Edit profile") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    avatarPicker
                    NanaSettingsCard {
                        sectionTitle("The basics", detail: "Let people know a little about you.")
                        lineField("Nickname", placeholder: "Your display name", value: $displayName, focus: .nickname)
                        dateField
                        lineField("Country or region", placeholder: "Where you’re from", value: $country, focus: .country)
                    }
                    NanaSettingsCard { genderField }
                    NanaSettingsCard { interestsField }
                    NanaSettingsCard { signatureField }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        }
        .onAppear(perform: loadProfile)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            focusedField = nil
            loadingPhoto = true
            photoError = nil
            Task { @MainActor in await loadPhoto(item) }
        }
        .fullScreenCover(isPresented: $showingDate) {
            NanaProfileBirthdayPicker(initialDate: birthDate) { birthDate = $0 }
        }
        .overlay {
            if let notice = sessionStore.sessionNotice {
                AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 6) {
            if focusedField != nil {
                Button("Done typing") { focusedField = nil }
                    .font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            NanaSettingsImageButton(title: loadingPhoto ? "Preparing photo…" : "Save changes", isEnabled: canSave) {
                focusedField = nil
                save()
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
        .frame(maxWidth: 520).frame(maxWidth: .infinity)
        .background(NanaPalette.deepSpace)
    }

    private var avatarPicker: some View {
        NanaSettingsCard {
            HStack(alignment: .center, spacing: 18) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    NanaAccountAvatarView(data: avatarData, size: dynamicTypeSize.isAccessibilitySize ? 72 : 92)
                }.disabled(loadingPhoto).accessibilityLabel("Change profile photo")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your profile photo").font(.headline)
                    Text("A familiar face makes it easier to connect.")
                        .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text(loadingPhoto ? "Preparing photo…" : "Change photo")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .background { Image("NanaCheckInGuideButton").resizable().accessibilityHidden(true) }
                }.disabled(loadingPhoto)
                if avatarData != nil {
                    Button("Reset") { avatarData = nil; resetAvatar = true }
                        .font(.subheadline).foregroundStyle(NanaPalette.electricLilac).frame(minWidth: 52, minHeight: 48)
                        .disabled(loadingPhoto).accessibilityLabel("Reset to default profile photo")
                }
            }
            if let photoError { Text(photoError).font(.footnote).foregroundStyle(NanaPalette.warning) }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(detail).font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lineField(_ title: String, placeholder: String, value: Binding<String>, focus: ProfileField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(focus == .nickname ? "Nickname · required" : title)
                .font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
            TextField(title, text: value, prompt: Text(placeholder).foregroundColor(.white.opacity(0.55)))
                .font(.body).foregroundStyle(.white).frame(minHeight: 48)
                .textInputAutocapitalization(.words).autocorrectionDisabled()
                .focused($focusedField, equals: focus).submitLabel(.next)
                .onSubmit { focusedField = focus == .nickname ? .country : .signature }
                .accessibilityLabel(title)
        }.id(focus)
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Date of birth").font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
            Button {
                focusedField = nil
                showingDate = true
            } label: {
                HStack(spacing: 12) {
                    Text(birthDate?.formatted(date: .abbreviated, time: .omitted) ?? "Choose your birthday")
                        .font(.body).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(birthDate == nil ? "Add" : "Edit").font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                }.frame(minHeight: 48)
            }.buttonStyle(.plain)
                .accessibilityLabel("Date of birth, \(birthDate?.formatted(date: .abbreviated, time: .omitted) ?? "not set")")
        }
    }

    private var genderField: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Gender", detail: "Choose what feels right for you.")
            LazyVGrid(columns: choiceColumns, spacing: 10) {
                ForEach(["Male", "Female", "Non-binary", "Prefer not to say"], id: \.self) { option in
                    choice(option, selected: gender == option) { focusedField = nil; gender = option }
                }
            }
        }
    }

    private var interestsField: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Interests", detail: "Pick the things you enjoy talking about.")
            Text("\(selectedInterests.count) selected").font(.caption).foregroundStyle(NanaPalette.electricLilac)
            LazyVGrid(columns: choiceColumns, spacing: 10) {
                ForEach(interestOptions, id: \.self) { interest in
                    choice(interest, selected: selectedInterests.contains(interest)) {
                        focusedField = nil
                        if !selectedInterests.insert(interest).inserted { selectedInterests.remove(interest) }
                    }
                }
            }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 48)
                .background {
                    Image("NanaCheckInGuideButton").resizable().saturation(selected ? 1 : 0)
                        .opacity(selected ? 1 : 0.28).accessibilityHidden(true)
                }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var signatureField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("About you", detail: "A short introduction, in your own words.")
            TextField("About you", text: $introduction, prompt: Text("What would you like people to know?").foregroundColor(.white.opacity(0.55)), axis: .vertical)
                .font(.body).foregroundStyle(.white).lineLimit(3...5)
                .focused($focusedField, equals: .signature).textInputAutocapitalization(.sentences)
                .onChange(of: introduction) { _, value in
                    if value.count > 160 { introduction = String(value.prefix(160)) }
                }
                .accessibilityLabel("About you, up to 160 characters")
            Text("\(introduction.count)/160").font(.caption.monospacedDigit()).foregroundStyle(NanaPalette.mutedWhite)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }.id(ProfileField.signature)
    }

    private func loadProfile() {
        guard editingAccountScope == nil, let profile = sessionStore.activeProfile else { return }
        editingAccountScope = profile.localAccountScope
        displayName = profile.displayName; country = profile.country; gender = profile.gender
        birthDate = profile.birthDate; selectedInterests = Set(profile.interests)
        avatarData = profile.avatarData; introduction = profile.introduction ?? ""
    }

    private func save() {
        guard let editingAccountScope else { return }
        if sessionStore.updateActiveProfile(displayName: displayName, country: country, avatarData: avatarData,
                                           accountScope: editingAccountScope, gender: gender, birthDate: birthDate,
                                           interests: selectedInterests.sorted(), introduction: introduction, resetAvatar: resetAvatar) {
            dismiss()
        }
    }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { loadingPhoto = false; selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), data.count <= 25_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024
                  ] as CFDictionary), let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8) else {
                photoError = "Choose a photo smaller than 25 MB."; return
            }
            guard editingAccountScope == sessionStore.activeProfile?.localAccountScope else { return }
            avatarData = jpeg; resetAvatar = false
        } catch { photoError = "Couldn't load this photo. Please try another one." }
    }
}

private struct NanaProfileBirthdayPicker: View {
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int
    @State private var day: Int
    private let calendar = Calendar(identifier: .gregorian)

    init(initialDate: Date?, onSelect: @escaping (Date) -> Void) {
        self.onSelect = onSelect
        let calendar = Calendar(identifier: .gregorian)
        let date = initialDate ?? calendar.date(byAdding: .year, value: -25, to: Date()) ?? Date()
        _year = State(initialValue: calendar.component(.year, from: date))
        _month = State(initialValue: calendar.component(.month, from: date))
        _day = State(initialValue: calendar.component(.day, from: date))
    }
    private var currentYear: Int { calendar.component(.year, from: Date()) }
    private var daysInMonth: Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 28 }
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 28
    }
    private var selectedDate: Date? {
        guard (1...daysInMonth).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
    private var isValidDate: Bool {
        guard let date = selectedDate else { return false }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: Date())
    }

    var body: some View {
        NanaProfilePage("Date of birth") {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose your birthday").font(.title3.weight(.semibold))
                    Text("Select a year, month and day. Your changes are applied when you tap Use this date.")
                        .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                    NanaSettingsCard {
                        Text(selectedDate?.formatted(date: .long, time: .omitted) ?? "Select a date")
                            .font(.headline).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        HStack(alignment: .top, spacing: 8) {
                            dateColumn("Year", values: Array((min(year, currentYear - 120)...currentYear).reversed()), selection: $year)
                            dateColumn("Month", values: Array(1...12), selection: $month)
                            dateColumn("Day", values: Array(1...daysInMonth), selection: $day)
                        }
                    }
                    if !isValidDate {
                        Text("Your birthday cannot be in the future.").font(.footnote).foregroundStyle(NanaPalette.warning)
                    }
                }.padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NanaSettingsImageButton(title: "Use this date", isEnabled: isValidDate) {
                    if let date = selectedDate { onSelect(calendar.startOfDay(for: date)); dismiss() }
                }
                .padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: 520).frame(maxWidth: .infinity)
                .background(NanaPalette.deepSpace)
            }
        }
        .onChange(of: year) { _, _ in day = min(day, daysInMonth) }
        .onChange(of: month) { _, _ in day = min(day, daysInMonth) }
    }

    private func dateColumn(_ title: String, values: [Int], selection: Binding<Int>) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
            ScrollViewReader { reader in
                ScrollView(showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(values, id: \.self) { value in
                            Button { selection.wrappedValue = value } label: {
                                Text(String(value)).font(.body.monospacedDigit()).minimumScaleFactor(0.75).lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background {
                                        if selection.wrappedValue == value {
                                            Image("NanaCheckInGuideButton").resizable().accessibilityHidden(true)
                                        }
                                    }
                            }
                            .buttonStyle(.plain).id(value)
                            .accessibilityLabel("\(title), \(value)")
                            .accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : [])
                        }
                    }
                }
                .frame(height: 264)
                .onAppear { reader.scrollTo(selection.wrappedValue, anchor: .center) }
                .onChange(of: selection.wrappedValue) { _, value in reader.scrollTo(value, anchor: .center) }
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct NanaProfilePage<Content: View>: View {
    let title: String
    let help: (() -> Void)?
    let content: Content
    @EnvironmentObject private var contentStore: NanaContentStore

    init(_ title: String, help: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                VStack(spacing: 0) {
                    NanaDetailPageHeader(title: title, trailingSymbol: "questionmark.circle", trailingLabel: "About \(title)", trailingAction: help)
                    content
                }
            }
            .foregroundStyle(NanaPalette.warmWhite)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaProfileActionSheet: View {
    let title: String
    let detail: String
    let actionTitle: String
    var destructive = true
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 23, weight: .bold))
            Text(detail).font(.system(size: 14)).foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
                action()
            } label: {
                Text(actionTitle).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(NanaPalette.deepSpace, in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
            if let secondaryTitle, let secondaryAction {
                Button {
                    dismiss()
                    secondaryAction()
                } label: {
                    Text(secondaryTitle).font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(NanaPalette.deepSpace, in: RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain)
            }
            Button { dismiss() } label: {
                Text("Close").font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(24)
        .presentationDetents([.height(secondaryTitle == nil ? 320 : 390), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color(red: 0.075, green: 0.055, blue: 0.105))
    }
}

private struct NanaRelationshipCard: View {
    let profile: NanaProfile
    var blocked = false
    let action: () -> Void
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let asset = profile.avatarAssetKey { NanaAssetImage(assetKey: asset) }
                else { NanaAvatarView(title: profile.displayName, assetKey: nil, size: 64) }
            }
            .frame(width: 66, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NanaPalette.violet, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(profile.age) · \(profile.region) · Lv.\(profile.level)")
                        .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                    if !blocked && contentStore.liveFriendRooms.contains(where: { $0.hostID == profile.id }) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit).frame(width: 28, height: 11)
                    }
                }
                Text(blocked ? "Hidden from your feed and rooms" : profile.introduction)
                    .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                VStack(spacing: 3) {
                    if !blocked {
                        Text("Check").font(.system(size: 9, weight: .bold).italic())
                            .foregroundStyle(.black).padding(.horizontal, 7)
                            .background(Color.green, in: Capsule())
                    }
                    Image(systemName: blocked ? "trash" : "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(NanaPalette.violet, in: RoundedRectangle(cornerRadius: 11))
                }.frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(blocked ? "Unblock \(profile.displayName)" : "View \(profile.displayName)")
        }
        .padding(12)
        .background(NanaPalette.deepSpace, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct NanaConnectionsView: View {
    let profile: NanaProfile
    let initialTab: String
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedPerson: NanaProfile?

    private var people: [NanaProfile] {
        switch initialTab {
        case "Followers": return contentStore.accountFollowers
        case "Following": return contentStore.followedProfiles
        default: return contentStore.mutualFriends
        }
    }

    var body: some View {
        NanaProfilePage(initialTab) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if people.isEmpty {
                        NanaEmptyState(title: "No \(initialTab.lowercased()) yet", detail: "Your \(initialTab.lowercased()) will appear here.", actionTitle: nil, action: nil)
                            .padding(.top, 64)
                    }
                    ForEach(people) { person in
                        VStack(alignment: .leading, spacing: 6) {
                            NanaRelationshipCard(profile: person) { selectedPerson = person }
                            if contentStore.isWelcomeFollower(person.id) {
                                Text("Welcome interaction · simulated locally")
                                    .font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .fullScreenCover(item: $selectedPerson) { NanaUserProfileView(profile: $0) }
    }
}

struct NanaWalletView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var showingHelp = false

    var body: some View {
        NanaProfilePage("Wallet", help: { showingHelp = true }) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: -22) {
                    balanceCard
                        .padding(.horizontal, 20)
                    rechargeOptions
                }
                .padding(.top, 8)
            }
        }
        .task {
            await contentStore.refresh(.wallet)
            coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
        }
        .accessibilityHidden(showingHelp)
        .overlay {
            if showingHelp {
                NanaAccountGuide(topic: .wallet) { showingHelp = false }
            }
        }
        .overlay {
            if let notice = coinStore.notice { AccountConsentNotice(notice: notice) { coinStore.dismissNotice() } }
        }
    }

    private var balanceCard: some View {
        Image("NanaWalletArtwork").resizable().scaledToFit()
            .overlay {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My balance").font(.system(size: 17, weight: .medium))
                        Text(contentStore.preference("hideCoinBalance", default: false) ? "••••" : coinStore.balance.formatted())
                            .font(.system(size: 14)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("coins").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                    }
                    // Reserve both illustrated sides of the supplied balance artwork.
                    .frame(width: geometry.size.width * 0.46, alignment: .leading)
                    .padding(.leading, geometry.size.width * 0.25)
                    .padding(.top, geometry.size.height * 0.17)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contentStore.preference("hideCoinBalance", default: false) ? "Balance hidden" : "My balance, \(coinStore.balance) coins")
    }

    private var rechargeOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recharge options")
                .font(.system(size: 15, weight: .medium))
            VStack(spacing: 12) {
                ForEach(NanaCoinStore.packs) { pack in packRow(pack) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The reference's list surface overlaps the lower edge of the banner.
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.28), location: 0),
                .init(color: Color.black.opacity(0.80), location: 0.11),
                .init(color: .black, location: 0.32)
            ], startPoint: .top, endPoint: .bottom)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        }
    }

    private func packRow(_ pack: NanaCoinPack) -> some View {
        HStack(spacing: 12) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.coins.formatted()).font(.system(size: 18, weight: .medium))
                Text("coins").font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
                Text("Includes \(pack.bonusCoins.formatted()) bonus")
                    .font(.system(size: 9)).foregroundStyle(NanaPalette.electricLilac)
            }
            Spacer(minLength: 8)
            Button { Task { await coinStore.purchase(pack: pack) } } label: {
                ZStack(alignment: .bottom) {
                    if pack.id == NanaCoinStore.packs.first?.id {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_073", contentMode: .fit)
                            .frame(width: 88, height: 88 * 84 / 156)
                    } else {
                        // Use the supplied blank violet capsule body; clip only its lower pointer.
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_043", contentMode: .fit)
                            .frame(width: 88, height: 88 * 56 / 142)
                            .frame(height: 88 * 44 / 142, alignment: .top)
                            .clipped()
                    }
                    Group {
                        if coinStore.purchasingProductID == pack.productID { ProgressView().tint(.white) }
                        else { Text(coinStore.products.first(where: { $0.id == pack.productID })?.displayPrice ?? pack.fallbackPrice) }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 76, height: 27)
                }
                .frame(width: 88, height: 48, alignment: .bottom)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(coinStore.purchasingProductID != nil)
                .overlay(alignment: .topTrailing) {
                    bonusTag(percent: pack.bonusPercent)
                        .offset(x: 10, y: -9)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("Buy \(pack.coins.formatted()) coins, including \(pack.bonusCoins.formatted()) bonus coins, for \(coinStore.products.first(where: { $0.id == pack.productID })?.displayPrice ?? pack.fallbackPrice)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minHeight: 72)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 13))
    }

    private func bonusTag(percent: Int) -> some View {
        // The original pack includes this unlettered tag; keep its shape, ring and highlights.
        NanaAssetImage(assetKey: "nana.voice.voice_asset_069", contentMode: .fit)
            .frame(width: 38, height: 38)
            .overlay {
                VStack(spacing: 0) {
                    Text("+\(percent)%").font(.system(size: 6.5, weight: .bold))
                    Text("EXTRA").font(.system(size: 5, weight: .bold))
                }
                .foregroundStyle(.white)
                // Text sits inside the blank flower, clear of its attachment ring.
                .offset(x: -2, y: 5)
            }
            .accessibilityLabel("\(percent) percent extra coins")
    }
}

private enum NanaAccountGuideTopic: Equatable {
    case checkIn
    case wallet

    var title: String { self == .checkIn ? "Daily check-in" : "Your Nana wallet" }
    var subtitle: String { self == .checkIn ? "Small visits. Steady progress." : "A little gift. A brighter room." }
    var artwork: String { self == .checkIn ? "NanaCheckInGuideCalendar" : "NanaWalletGuideIllustration" }
    var footnote: String {
        self == .checkIn
            ? "Your check-in calendar is saved on this device for your account."
            : "Wallet coins and daily check-in activity points are separate."
    }
}

/// Original raster artwork provides all decorative surfaces; native text stays readable by VoiceOver.
private struct NanaAccountGuide: View {
    let topic: NanaAccountGuideTopic
    let onDismiss: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.64)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            Image(topic.artwork)
                                .resizable().scaledToFit()
                                .frame(height: 100)
                                .accessibilityHidden(true)

                            VStack(spacing: 6) {
                                Text(topic.title)
                                    .font(.title2.weight(.bold))
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($titleFocused)
                                Text(topic.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(red: 0.78, green: 0.71, blue: 0.87))
                            }
                            .multilineTextAlignment(.center)

                            if topic == .checkIn {
                                HStack(spacing: 12) {
                                    Text("+10")
                                        .font(.system(size: 40, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(red: 1, green: 0.63, blue: 0.85))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("ACTIVITY POINTS").font(.caption.weight(.semibold)).tracking(1)
                                        Text("Free · Once a day").font(.footnote)
                                            .foregroundStyle(Color(red: 0.78, green: 0.71, blue: 0.87))
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("10 activity points, free, once a day")
                            }

                            VStack(alignment: .leading, spacing: 18) {
                                if topic == .checkIn {
                                    rule("01", title: "Grow your level", message: "Every 200 points earns a level. Activity points are separate from wallet coins.")
                                    rule("02", title: "A fresh start each day", message: "Return after midnight on your device. Missed days can’t be claimed later.")
                                } else {
                                    rule("01", title: "Send a little appreciation", message: "Use coins for room gifts. Free gifts never reduce your balance.")
                                    rule("02", title: "The bonus is already included", message: "Pack totals include bonus coins. EXTRA is the bonus percentage of the base amount.")
                                    rule("03", title: "Confirmed by the App Store", message: "Apple’s checkout price applies. Coins are added after payment is verified; pending purchases wait for approval.")
                                }
                            }

                            Text(topic.footnote)
                                .font(.caption).lineSpacing(3)
                                .foregroundStyle(Color(red: 0.66, green: 0.60, blue: 0.74))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 20).padding(.bottom, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background {
                                Image("NanaCheckInGuideButton")
                                    .resizable().accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 26)
                .frame(width: min(390, max(0, geometry.size.width - 32)), height: min(650, max(0, geometry.size.height - 24)))
                .background {
                    Image("NanaCheckInGuideSurface")
                        .resizable().accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .accessibilityAction(.escape, onDismiss)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear { titleFocused = true }
    }

    private func rule(_ number: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(Color(red: 0.87, green: 0.61, blue: 1))
                .padding(.top, 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).lineSpacing(3)
                    .foregroundStyle(Color(red: 0.78, green: 0.71, blue: 0.87))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NanaCheckInView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var monthOffset = 0
    @State private var showingHelp = false
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var month: Date {
        let today = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return calendar.date(byAdding: .month, value: monthOffset, to: start) ?? start
    }
    private var days: [Date] {
        let offset = (calendar.component(.weekday, from: month) + 5) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month),
              let monthDays = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let cellCount = ((offset + monthDays.count + 6) / 7) * 7
        return (0..<cellCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var monthTitle: String {
        String(format: "%04d/%02d", calendar.component(.year, from: month), calendar.component(.month, from: month))
    }

    var body: some View {
        NanaProfilePage("Daily check-in", help: { showingHelp = true }) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Keep the binding rings and calendar character at their original proportions.
                    Image("NanaCheckInArtwork")
                        .resizable().scaledToFit()
                        .accessibilityHidden(true)
                        .overlay {
                            GeometryReader { geometry in
                                let heroHeight = geometry.size.width * 430 / 700
                                VStack(spacing: 0) {
                                    hero(width: geometry.size.width)
                                        .frame(height: heroHeight)
                                    calendarCard(height: geometry.size.height - heroHeight)
                                }
                            }
                        }
                    rewardSummary
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .accessibilityHidden(showingHelp)
        .overlay {
            if showingHelp {
                NanaAccountGuide(topic: .checkIn) { showingHelp = false }
            }
        }
    }

    private func hero(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                Text(contentStore.checkedInToday ? "Checked in today" : "「 Sign in today 」")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    Text("Lv.\(contentStore.activityLevel)")
                    (Text("\(contentStore.activityPoints % 200)").foregroundColor(NanaPalette.softPink) + Text("/200"))
                }.font(.system(size: 11))
                activityProgress
                Button { contentStore.performCheckIn() } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_146", contentMode: .fit)
                        .frame(width: 102, height: 29).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain).disabled(contentStore.checkedInToday)
                    .opacity(contentStore.checkedInToday ? 0.55 : 1)
                    .accessibilityLabel(contentStore.checkedInToday ? "Checked in today" : "Check in")
            }
            .frame(width: width * 0.40, alignment: .leading)
            .padding(.leading, width * 0.075)
            Spacer(minLength: 0)
        }
        .padding(.top, width * 0.035)
    }

    private var activityProgress: some View {
        GeometryReader { geometry in
            let progress = CGFloat(contentStore.activityPoints % 200) / 200
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.85))
                Capsule().fill(NanaPalette.violet).frame(width: geometry.size.width * progress)
                Circle().fill(NanaPalette.violet).frame(width: 9, height: 9)
                    .offset(x: max(0, (geometry.size.width - 9) * progress))
            }
        }.frame(height: 4)
            .accessibilityLabel("Activity progress, \(contentStore.activityPoints % 200) of 200 points")
    }

    private func calendarCard(height: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        let rowCount = max(1, days.count / 7)
        let dayHeight = max(24, (height - 180) / CGFloat(rowCount))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                monthButton("nana.voice.voice_asset_030", label: "Previous month", offset: -1)
                Text(monthTitle).font(.system(size: 15)).monospacedDigit()
                monthButton("nana.voice.voice_asset_032", label: "Next month", offset: 1)
            }.frame(maxWidth: .infinity)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day).font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite).frame(height: 22)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days, id: \.self) { date in dayCell(date).frame(height: dayHeight) }
            }
            Spacer(minLength: 12)
            Button { contentStore.performCheckIn() } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_128", contentMode: .fit)
                    .overlay(alignment: .trailing) {
                        Text("+10 pts").font(.system(size: 10)).padding(.trailing, 14)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(contentStore.checkedInToday)
            .opacity(contentStore.checkedInToday ? 0.6 : 1)
            .padding(.horizontal, 16)
            .accessibilityLabel(contentStore.checkedInToday ? "Checked in today" : "Clock in, receive 10 activity points")
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 18)
        .frame(height: height)
    }

    private func monthButton(_ assetKey: String, label: String, offset: Int) -> some View {
        Button { monthOffset += offset } label: {
            NanaAssetImage(assetKey: assetKey, contentMode: .fit)
                .frame(width: 12, height: 12)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func dayCell(_ date: Date) -> some View {
        let checked = contentStore.personal.checkInDays.contains(contentStore.dayKey(date))
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.19, green: 0.20, blue: 0.21))
            if checked {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_149", contentMode: .fit)
                    .frame(width: 17, height: 17)
            } else {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12))
                    .foregroundStyle(calendar.isDateInToday(date) ? NanaPalette.softPink : .white.opacity(inMonth ? 0.8 : 0.25))
            }
        }
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(checked ? "checked in" : "not checked in")")
    }

    private var rewardSummary: some View {
        HStack(spacing: 10) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_018", contentMode: .fit)
                .frame(width: 34, height: 38)
                .accessibilityHidden(true)
            Text("A little progress, every day")
                .font(.system(size: 12)).foregroundStyle(Color(red: 0.35, green: 0.77, blue: 0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("Free").font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.35, green: 0.77, blue: 0.92))
        }
        .padding(12)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum NanaCollectionDestination: String, Identifiable {
    case store, backpack
    var id: String { rawValue }
    var title: String { self == .store ? "Store" : "Backpack" }
}

private struct NanaCollectionView: View {
    let destination: NanaCollectionDestination
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var selectedGiftID = NanaGift.roomCatalog[0].id
    @State private var quantity = 1
    private var selectedGift: NanaGift { NanaGift.roomCatalog.first { $0.id == selectedGiftID } ?? NanaGift.roomCatalog[0] }
    private var isStore: Bool { destination == .store }

    var body: some View {
        NanaProfilePage(destination.title) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 22) {
                        ForEach(NanaGift.roomCatalog) { gift in giftTile(gift) }
                    }
                    if isStore {
                        // The reference repeats the same eight gifts as standalone artwork below the priced tiles.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 44) {
                            ForEach(NanaGift.roomCatalog) { gift in
                                Button { selectedGiftID = gift.id } label: {
                                    NanaAssetImage(assetKey: gift.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit)
                                        .frame(height: 72).padding(.horizontal, 7)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Select \(gift.title)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
                .frame(maxWidth: 390).frame(maxWidth: .infinity)
                if !isStore {
                    Text("Free gifts are ready to use in rooms.")
                        .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite).padding(20)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if isStore { purchaseBar } }
        .overlay {
            if let notice = coinStore.notice {
                AccountConsentNotice(notice: notice) { coinStore.dismissNotice() }
            }
        }
    }

    private func giftTile(_ gift: NanaGift) -> some View {
        Button { selectedGiftID = gift.id } label: {
            VStack(spacing: 10) {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ZStack {
                            if selectedGiftID == gift.id {
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_131", contentMode: .fit)
                                NanaAssetImage(assetKey: gift.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit).padding(11)
                            } else if gift.id == "gift-music-note" {
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_131", contentMode: .fit)
                                    .saturation(0).opacity(0.24)
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_077", contentMode: .fit).padding(11)
                            } else {
                                NanaAssetImage(assetKey: giftTileAsset(gift), contentMode: .fit)
                            }
                        }
                    }
                HStack(spacing: 3) {
                    if isStore && gift.coinCost > 0 {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 12, height: 12)
                    }
                    Text(gift.coinCost == 0 ? "Free" : isStore ? "\(gift.coinCost)" : "× 0")
                        .font(.system(size: 12)).foregroundStyle(gift.coinCost == 0 ? .green : NanaPalette.mutedWhite)
                }
            }
        }.buttonStyle(.plain).accessibilityLabel("\(gift.title), \(gift.coinCost == 0 ? "Free" : "\(gift.coinCost) coins")")
    }

    private func giftTileAsset(_ gift: NanaGift) -> String {
        switch gift.id {
        case "gift-gamepad": return "nana.voice.voice_asset_123"
        case "gift-karaoke": return "nana.voice.voice_asset_144"
        case "gift-drum": return "nana.voice.voice_asset_148"
        case "gift-headphones": return "nana.voice.voice_asset_121"
        case "gift-microphone": return "nana.voice.voice_asset_120"
        case "gift-record": return "nana.voice.voice_asset_112"
        case "gift-keyboard": return "nana.voice.voice_asset_082"
        default: return "nana.voice.voice_asset_130"
        }
    }

    private var purchaseBar: some View {
        HStack(spacing: 6) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(contentStore.preference("hideCoinBalance", default: false) ? "••••" : coinStore.balance.formatted()).font(.system(size: 13, weight: .medium))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                Text("Balance").font(.system(size: 9)).foregroundStyle(NanaPalette.mutedWhite)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contentStore.preference("hideCoinBalance", default: false) ? "Balance hidden" : "Balance, \(coinStore.balance) coins")
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { quantity = max(1, quantity - 1) } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_117", contentMode: .fit)
                        .frame(width: 20, height: 20).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                    .disabled(quantity == 1).accessibilityLabel("Decrease quantity")
                Text("\(quantity)").font(.system(size: 13)).monospacedDigit().frame(width: 18)
                    .accessibilityLabel("Quantity, \(quantity)")
                Button { quantity = min(99, quantity + 1) } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_116", contentMode: .fit)
                        .frame(width: 20, height: 20).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                    .disabled(quantity == 99).accessibilityLabel("Increase quantity")
                Button { contentStore.explainUnavailable("Buying items") } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_169", contentMode: .fit)
                        .frame(width: 56, height: 29).frame(height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Buy \(selectedGift.title), quantity \(quantity), \(selectedGift.coinCost * quantity) coins")
            }
            .buttonStyle(.plain).padding(.trailing, 4).fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(.horizontal, 14).frame(height: 76)
        .background {
            // Crop transparent export margins in the view; preserve the original raster surface.
            Image("NanaStoreCheckoutSurface").resizable()
                .frame(height: 152).frame(height: 76).clipped().accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            Text(selectedGift.coinCost == 0 ? "Free gift" : "Total: \(selectedGift.coinCost * quantity) coins")
                .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).offset(y: -22)
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 8)
    }
}

private struct NanaLevelView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        NanaProfilePage("My level") {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("My level").font(.system(size: 16, weight: .semibold))
                            Text("Lv.\(contentStore.activityLevel)").font(.system(size: 30, weight: .bold))
                            Text("Grow with daily check-ins.").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                        }
                        Spacer()
                        Image("NanaLevelGem").resizable().scaledToFit().frame(width: 140, height: 118)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Days checked in").font(.system(size: 13))
                        Label("\(contentStore.personal.checkInDays.count)", systemImage: "calendar.badge.checkmark")
                            .font(.system(size: 27, weight: .semibold))
                        ProgressView(value: Double(contentStore.activityPoints % 200), total: 200).tint(.white)
                        Text("Next level: \(contentStore.activityPoints % 200)/200 points")
                            .font(.system(size: 12))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.orange, NanaPalette.neonPink, NanaPalette.violet, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20))
                }.padding(20)
            }
        }
    }
}

private struct NanaFeedbackView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var topic = ""
    @State private var message = ""
    @State private var loaded = false
    @FocusState private var focused: Bool
    private var canSubmit: Bool { !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NanaProfilePage("Feedback") {
            ScrollView {
                VStack(spacing: 14) {
                    TextField("Please enter the question topic", text: $topic)
                        .font(.system(size: 14)).padding(15).focused($focused)
                        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: topic) { _, value in if value.count > 80 { topic = String(value.prefix(80)) } }
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Please enter the details of the question").font(.system(size: 14))
                                .foregroundStyle(NanaPalette.mutedWhite).padding(.horizontal, 19).padding(.top, 22)
                        }
                        TextEditor(text: $message).scrollContentBackground(.hidden)
                            .font(.system(size: 14)).padding(14).focused($focused).frame(height: 190)
                    }
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: message) { _, value in if value.count > 2000 { message = String(value.prefix(2000)) } }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Submit") {
                focused = false
                if contentStore.saveFeedback(topic: topic, message: message) { topic = ""; message = "" }
            }
            .buttonStyle(NanaPrimaryButtonStyle()).disabled(!canSubmit).opacity(canSubmit ? 1 : 0.45)
            .padding(.horizontal, 44).padding(.vertical, 22)
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            topic = contentStore.draft(for: "feedback.topic")
            message = contentStore.draft(for: "feedback")
        }
    }
}

private struct NanaSettingsRow: View {
    let title: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 14))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                Spacer()
                if !destructive {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                }
            }.frame(minHeight: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct NanaSettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 15)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 13))
    }
}

private enum NanaSettingsAction: String, Identifiable {
    case logout, deleteAccount
    var id: String { rawValue }
    var title: String { self == .deleteAccount ? "Delete local account?" : "Log out?" }
    var detail: String {
        self == .deleteAccount
            ? "Permanently remove this device’s account profile, photos, drafts, check-ins, blocks and coin balance. This cannot be undone. Other saved accounts are kept. This does not delete remote service data or revoke Sign in with Apple. It does not refund purchases; Apple purchase history stays with Apple."
            : "You will return to the login screen. Your saved profile, photos and coin balance stay with this account."
    }
    var actionTitle: String { self == .deleteAccount ? "Delete local account" : "Log out" }
}

private struct NanaAccountExitConfirmation: View {
    let action: NanaSettingsAction
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.68).ignoresSafeArea().onTapGesture(perform: cancel)
                VStack(spacing: 16) {
                    Image("NanaSettingsSecurity").resizable().scaledToFit().frame(height: 74).accessibilityHidden(true)
                    Text(action.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    ScrollView {
                        Text(action.detail).font(.subheadline).foregroundStyle(NanaPalette.mutedWhite)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    NanaSettingsImageButton(title: action.actionTitle, action: confirm)
                    Button("Cancel", action: cancel).font(.subheadline.weight(.semibold))
                        .foregroundStyle(NanaPalette.electricLilac).frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(24).frame(maxWidth: 350).frame(height: min(action == .deleteAccount ? 560 : 390, max(300, geometry.size.height - 36)))
                .background { Image("NanaSettingsCardSurface").resizable(capInsets: EdgeInsets(top: 54, leading: 54, bottom: 54, trailing: 54)) }
                .padding(.horizontal, 20)
                .foregroundStyle(.white)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAction(.escape) { cancel() }
    }
}

struct NanaSettingsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var showingPrivacy = false
    @State private var showingNotice = false
    @State private var showingAbout = false
    @State private var showingSecurity = false
    @State private var showingAccounts = false
    @State private var showingStorage = false
    @State private var showingBlacklist = false
    @State private var showingCommunity = false
    @State private var selectedPolicy: AccountPolicyDocument?
    @State private var action: NanaSettingsAction?

    var body: some View {
        NanaProfilePage("Settings") {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "Account security") { showingSecurity = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Accounts") { showingAccounts = true }
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "Privacy Settings") { showingPrivacy = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Blocked accounts") { showingBlacklist = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Notifications") { showingNotice = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Storage & cache") { showingStorage = true }
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "User Agreement") { selectedPolicy = .userAgreement }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Privacy Policy") { selectedPolicy = .privacyPolicy }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Community Guidelines") { showingCommunity = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "About Us") { showingAbout = true }
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "Delete account", destructive: true) { action = .deleteAccount }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Log out", destructive: true) { action = .logout }
                    }
                }.padding(20)
            }
        }
        .fullScreenCover(isPresented: $showingPrivacy) { NanaPrivacySettingsView() }
        .fullScreenCover(isPresented: $showingNotice) { NanaNoticeSettingsView() }
        .fullScreenCover(isPresented: $showingAbout) { NanaAboutView() }
        .fullScreenCover(isPresented: $showingSecurity) { NanaAccountSecurityView() }
        .fullScreenCover(isPresented: $showingAccounts) { NanaAccountsView() }
        .fullScreenCover(isPresented: $showingStorage) { NanaStorageSettingsView() }
        .fullScreenCover(isPresented: $showingBlacklist) { NanaBlacklistView() }
        .fullScreenCover(isPresented: $showingCommunity) { NanaCommunityGuidelinesView() }
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
        .accessibilityHidden(action != nil || sessionStore.accountExitProgress != nil)
        .overlay {
            if let selected = action {
                NanaAccountExitConfirmation(action: selected, cancel: { action = nil }) {
                    action = nil
                    Task { await sessionStore.exitAccount(deleting: selected == .deleteAccount, contentStore: contentStore, coinStore: coinStore) }
                }
            }
        }
        .overlay {
            if let notice = sessionStore.sessionNotice { AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil } }
        }
        .overlay { if let progress = sessionStore.accountExitProgress { NanaAccountExitOverlay(progress: progress) } }
    }
}

private struct NanaSettingsDetailPage<Content: View>: View {
    let title: String
    let artwork: String
    let headline: String
    let detail: String
    let content: Content

    init(title: String, artwork: String, headline: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.artwork = artwork
        self.headline = headline
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        NanaProfilePage(title) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(artwork).resizable().scaledToFit().frame(width: 110, height: 104)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(headline).font(.title3.weight(.semibold))
                            Text(detail).font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 8)
                    content
                }.padding(.horizontal, 20).padding(.bottom, 28)
                    .frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
        }
    }
}

private struct NanaSettingsCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background {
                Image("NanaSettingsCardSurface")
                    .resizable(capInsets: EdgeInsets(top: 54, leading: 54, bottom: 54, trailing: 54))
                    .accessibilityHidden(true)
            }
    }
}

private struct NanaSettingsImageButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background { Image("NanaCheckInGuideButton").resizable().accessibilityHidden(true) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }
}

private struct NanaPreferenceRow: View {
    let title: String
    let detail: String
    let key: String
    var defaultValue = false
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        NanaSettingsCard {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                choice("On", value: true)
                choice("Off", value: false)
            }
        }
    }
    private func choice(_ label: String, value: Bool) -> some View {
        let selected = contentStore.preference(key, default: defaultValue) == value
        return Button { contentStore.setPreference(key, value: value) } label: {
            Text(label).font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    Image("NanaCheckInGuideButton").resizable()
                        .saturation(selected ? 1 : 0).opacity(selected ? 1 : 0.25)
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(title): \(label)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NanaPrivacySettingsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingBlacklist = false
    var body: some View {
        NanaSettingsDetailPage(title: "Privacy", artwork: "NanaSettingsPrivacy", headline: "Your space, your choice", detail: "Control what appears on this device.") {
            NanaPreferenceRow(title: "Hide coin balance", detail: "Mask your balance in My Profile, Wallet, Store and the room gift picker.", key: "hideCoinBalance")
            NanaPreferenceRow(title: "Keep email concealed", detail: "Open Account security with your email hidden. You can reveal it when needed.", key: "concealAccountEmail", defaultValue: true)
            NanaPreferenceRow(title: "Pause room carousel", detail: "Browse featured rooms at your own pace. Swipe to move between rooms.", key: "pauseRoomCarousel")
            NanaSettingsCard {
                Text("People you’ve blocked").font(.subheadline.weight(.semibold))
                Text("Review blocked accounts or let someone appear again.").font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                NanaSettingsImageButton(title: "Manage blocked accounts") { showingBlacklist = true }
                Button("Photo and device permissions") { nanaOpenDeviceSettings() }
                    .font(.footnote).foregroundStyle(NanaPalette.electricLilac).frame(minHeight: 44)
            }
        }
        .fullScreenCover(isPresented: $showingBlacklist) { NanaBlacklistView() }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }
}

@MainActor
private func nanaOpenDeviceSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

/// One device-local reminder, resynchronized when the signed-in account changes.
@MainActor
enum NanaCheckInReminder {
    enum ReminderError: Error { case permissionRequired }
    static let identifier = "nana.daily-check-in"
    static func configure(enabled: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            return
        }
        let settings = await center.notificationSettings()
        try Task.checkCancellation()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { throw ReminderError.permissionRequired }
        let content = UNMutableNotificationContent()
        content.title = "A little time for you"
        content.body = "Open Nana to check your daily calendar."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 0), repeats: true)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

private struct NanaNoticeSettingsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var isWorking = false
    @State private var feedback: String?
    @State private var hasScheduledReminder = false
    private var allowed: Bool { authorization == .authorized || authorization == .provisional }
    private var reminderEnabled: Bool { contentStore.preference("dailyCheckInReminder", default: false) }
    private var status: String {
        switch authorization {
        case .authorized: return "Notifications allowed"
        case .provisional: return "Quiet notifications allowed"
        case .denied: return "Notifications are off in iOS"
        case .notDetermined: return "Permission not requested"
        case .ephemeral: return "Temporary permission"
        @unknown default: return "Check iOS notification settings"
        }
    }
    var body: some View {
        NanaSettingsDetailPage(title: "Notifications", artwork: "NanaSettingsNotifications", headline: "Only the reminders you want", detail: "iOS permission and your daily reminder, in one place.") {
            NanaSettingsCard {
                Text("SYSTEM PERMISSION").font(.caption.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                Text(status).font(.headline)
                Text("Manage lock-screen previews, sounds and banners in iOS.").font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                NanaSettingsImageButton(title: authorization == .notDetermined ? "Enable notifications" : "Open iOS settings", isEnabled: !isWorking) {
                    if authorization == .notDetermined { Task { await requestPermission() } }
                    else { nanaOpenDeviceSettings() }
                }
            }
            NanaSettingsCard {
                Text("Daily check-in reminder").font(.headline)
                Text("One gentle reminder at 8:00 PM, using your device’s local time. No account details appear in the notification.")
                    .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                Text(reminderEnabled ? (allowed && hasScheduledReminder ? "Scheduled for 8:00 PM" : "Paused — check notification permission") : "Reminder is off")
                    .font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                NanaSettingsImageButton(title: reminderEnabled ? "Turn reminder off" : "Turn reminder on", isEnabled: !isWorking && (allowed || reminderEnabled)) {
                    Task { await changeReminder() }
                }
            }
            if let feedback { Text(feedback).font(.footnote).foregroundStyle(NanaPalette.electricLilac).accessibilityAddTraits(.updatesFrequently) }
        }
        .task { await refreshPermission() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshPermission() } } }
    }
    private func refreshPermission() async {
        let scope = sessionStore.activeProfile?.localAccountScope
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard scope == sessionStore.activeProfile?.localAccountScope, scope != nil else { return }
        if allowed && reminderEnabled {
            do { try await NanaCheckInReminder.configure(enabled: true) }
            catch { feedback = "Couldn’t restore the reminder. Try turning it off and on again." }
        }
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        hasScheduledReminder = requests.contains { $0.identifier == NanaCheckInReminder.identifier }
    }
    private func requestPermission() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermission()
        } catch { feedback = "Couldn’t request permission. Try again or open iOS settings." }
    }
    private func changeReminder() async {
        let scope = sessionStore.activeProfile?.localAccountScope
        let enabled = !reminderEnabled
        isWorking = true
        defer { isWorking = false }
        do {
            try await NanaCheckInReminder.configure(enabled: enabled)
            guard scope == sessionStore.activeProfile?.localAccountScope, scope != nil else {
                try? await NanaCheckInReminder.configure(enabled: false)
                return
            }
            if contentStore.setPreference("dailyCheckInReminder", value: enabled) {
                feedback = enabled ? "Reminder set for 8:00 PM." : "Daily reminder turned off."
                await refreshPermission()
            } else {
                try? await NanaCheckInReminder.configure(enabled: !enabled)
                feedback = "Couldn’t save this change. Please try again."
            }
        } catch { feedback = "Couldn’t update the reminder. Please try again." }
    }
}

private struct NanaAboutView: View {
    @State private var selectedPolicy: AccountPolicyDocument?
    @State private var showingCommunity = false
    var body: some View {
        NanaProfilePage("About Us") {
            ScrollView {
                VStack(spacing: 22) {
                    Image("NanaBrandIcon").resizable().scaledToFit()
                        .frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 22)
                    Text("Nana · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "User Agreement") { selectedPolicy = .userAgreement }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Privacy Policy") { selectedPolicy = .privacyPolicy }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Community Guidelines") { showingCommunity = true }
                    }
                }.padding(20)
            }
        }
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
        .fullScreenCover(isPresented: $showingCommunity) { NanaCommunityGuidelinesView() }
    }
}

private struct NanaAccountSecurityView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var emailRevealed = false
    @State private var showingEdit = false
    @State private var checkingCredential = false
    @State private var feedback: String?
    private var email: String { sessionStore.activeProfile?.emailAddress ?? "" }
    private var concealedEmail: String {
        guard let separator = email.firstIndex(of: "@") else { return "Not shared" }
        return String(email.prefix(1)) + "•••" + String(email[separator...])
    }
    var body: some View {
        NanaSettingsDetailPage(title: "Account security", artwork: "NanaSettingsSecurity", headline: "Know your account", detail: "Review your identity and keep your details close.") {
            NanaSettingsCard {
                Text(sessionStore.activeProfile?.displayName ?? "Your account").font(.headline)
                Text(sessionStore.activeProfile?.signInMethod == "apple" ? "Sign in with Apple" : "Email profile")
                    .font(.footnote).foregroundStyle(NanaPalette.electricLilac)
                Text(email.isEmpty ? "Email not shared" : emailRevealed ? email : concealedEmail)
                    .font(.subheadline).textSelection(.enabled).lineLimit(2)
                if !email.isEmpty {
                    HStack(spacing: 16) {
                        Button(emailRevealed ? "Hide email" : "Show email") { emailRevealed.toggle() }
                        Button("Copy email") {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": email]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                            feedback = "Email copied. The clipboard entry expires in two minutes."
                        }
                    }.font(.footnote.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac).frame(minHeight: 44)
                }
                NanaSettingsImageButton(title: "Edit profile details") { showingEdit = true }
            }
            NanaSettingsCard {
                Text("Sign-in protection").font(.headline)
                if sessionStore.activeProfile?.signInMethod == "apple" {
                    Text("Check whether Apple still authorizes this sign-in. Manage your Apple password and trusted devices in iOS Settings.")
                        .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                    NanaSettingsImageButton(title: checkingCredential ? "Checking…" : "Check Apple access", isEnabled: !checkingCredential) {
                        Task {
                            checkingCredential = true
                            let authorized = await sessionStore.validateAppleSession()
                            checkingCredential = false
                            if authorized {
                                feedback = "Apple access checked just now."
                            } else if sessionStore.activeProfile != nil {
                                feedback = "The check did not complete. Please try again."
                            }
                        }
                    }
                } else {
                    Text("This email identifies your profile on this device. It is not a verified mailbox. Password changes and remote session management require the account service.")
                        .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                }
            }
            Text("Never share a password or verification code in a room or conversation.")
                .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
            if let feedback { Text(feedback).font(.footnote).foregroundStyle(NanaPalette.electricLilac).accessibilityAddTraits(.updatesFrequently) }
        }
        .onAppear { emailRevealed = !contentStore.preference("concealAccountEmail", default: true) }
        .fullScreenCover(isPresented: $showingEdit) { NanaEditProfileView() }
        .overlay {
            if let notice = sessionStore.sessionNotice { AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil } }
        }
    }
}

private struct NanaAccountsView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var confirmingEntry = false
    @State private var selectedEmail = ""
    var body: some View {
        NanaSettingsDetailPage(title: "Accounts", artwork: "NanaSettingsAccounts", headline: "Keep your accounts separate", detail: "Each account keeps its own profile, photos and coin balance.") {
            ForEach(sessionStore.savedProfiles, id: \.localAccountScope) { profile in
                NanaSettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.displayName).font(.headline)
                            Text(profile.signInMethod == "apple" ? "Apple account" : "Email profile")
                                .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                        }
                        Spacer()
                        if profile.localAccountScope == sessionStore.activeProfile?.localAccountScope {
                            Text("Current").font(.caption.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                        }
                    }
                    if profile.localAccountScope != sessionStore.activeProfile?.localAccountScope {
                        NanaSettingsImageButton(title: "Continue to sign-in") {
                            selectedEmail = profile.signInMethod == "apple" ? "" : profile.emailAddress
                            confirmingEntry = true
                        }
                    }
                }
            }
            if confirmingEntry {
                NanaSettingsCard {
                    Text("Leave this account?").font(.headline)
                    Text("You’ll return to sign-in. Saved profiles remain on this device; choosing a profile does not sign you in automatically.")
                        .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                    NanaSettingsImageButton(title: "Continue") { sessionStore.startAccountEntry(emailAddress: selectedEmail) }
                    Button("Stay here") { confirmingEntry = false }.frame(maxWidth: .infinity, minHeight: 44)
                        .font(.subheadline).foregroundStyle(NanaPalette.electricLilac)
                }
            } else {
                NanaSettingsImageButton(title: "Add another account") { selectedEmail = ""; confirmingEntry = true }
            }
        }
        .overlay {
            if let notice = sessionStore.sessionNotice { AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil } }
        }
    }
}

private struct NanaStorageSettingsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var contentBytes: Int64 = 0
    @State private var networkBytes: Int64 = 0
    @State private var confirming = false
    @State private var feedback: String?
    private func size(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
    var body: some View {
        NanaSettingsDetailPage(title: "Storage & cache", artwork: "NanaSettingsStorage", headline: "A little room to breathe", detail: "Remove temporary content without losing your account.") {
            NanaSettingsCard {
                Text("TEMPORARY DATA").font(.caption.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                Text(size(contentBytes + networkBytes)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                HStack { Text("Downloaded content"); Spacer(); Text(size(contentBytes)).monospacedDigit() }.font(.footnote)
                HStack { Text("Network cache"); Spacer(); Text(size(networkBytes)).monospacedDigit() }.font(.footnote)
                Text("In-memory video previews are also cleared. These are not included in the size above.")
                    .font(.caption).foregroundStyle(NanaPalette.mutedWhite)
                Button("Refresh size") { refreshSize() }.font(.footnote.weight(.semibold))
                    .foregroundStyle(NanaPalette.electricLilac).frame(minHeight: 44)
            }
            NanaSettingsCard {
                Text("Your keepsakes stay").font(.headline)
                Text("Uploaded photos, drafts, check-ins, blocked accounts, preferences and coins are kept. Content can download again when you browse.")
                    .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
            }
            if confirming {
                NanaSettingsCard {
                    Text("Clear temporary data now?").font(.headline)
                    NanaSettingsImageButton(title: "Clear cache") {
                        let succeeded = contentStore.clearCache(showNotice: false)
                        confirming = false
                        refreshSize()
                        feedback = succeeded ? "Cache cleared. Your personal data is safe." : "Couldn’t clear the cache. Please try again."
                    }
                    Button("Cancel") { confirming = false }.frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(NanaPalette.electricLilac)
                }
            } else {
                NanaSettingsImageButton(title: "Clear temporary data") { confirming = true }
            }
            if let feedback { Text(feedback).font(.footnote).foregroundStyle(NanaPalette.electricLilac).accessibilityAddTraits(.updatesFrequently) }
        }
        .onAppear { refreshSize() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshSize() } }
    }
    private func refreshSize() {
        contentBytes = contentStore.downloadedCacheBytes
        networkBytes = contentStore.networkCacheBytes
    }
}

private struct NanaBlacklistView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var feedback: String?
    var body: some View {
        NanaSettingsDetailPage(title: "Blocked accounts", artwork: "NanaSettingsPrivacy", headline: "Your boundaries matter", detail: "Only accounts you’ve blocked appear here. Unblocking does not undo a separate report.") {
            if let feedback {
                Text(feedback).font(.footnote).foregroundStyle(NanaPalette.electricLilac)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if contentStore.hiddenProfiles.isEmpty {
                NanaSettingsCard {
                    Text("No blocked accounts").font(.headline)
                    Text("If you block someone from a profile, room or post, you can manage them here.")
                        .font(.subheadline).foregroundStyle(NanaPalette.mutedWhite)
                }
            } else {
                Text("\(contentStore.hiddenProfiles.count) blocked").font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                ForEach(contentStore.hiddenProfiles) { profile in
                    NanaSettingsCard {
                        HStack(spacing: 12) {
                            NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 52)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(profile.displayName).font(.headline)
                                if !profile.region.isEmpty { Text(profile.region).font(.footnote).foregroundStyle(NanaPalette.mutedWhite) }
                            }
                            Spacer(minLength: 0)
                        }
                        NanaSettingsImageButton(title: "Unblock") {
                            if contentStore.unhide(profileID: profile.id) {
                                feedback = "\(profile.displayName) is no longer blocked."
                            }
                        }.accessibilityLabel("Unblock \(profile.displayName)")
                    }
                }
            }
        }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }
}

private struct NanaCommunityGuidelinesView: View {
    @State private var showingBlacklist = false
    private let rules: [(String, String)] = [
        ("Make room for each other", "Nana brings people together through live rooms, music and conversation. Respect different backgrounds and opinions. No hate speech, slurs, targeted humiliation, threats, stalking or repeated unwanted contact. A disagreement is never a reason to harass someone."),
        ("Keep rooms safe", "Do not share pornography, sexual solicitation, graphic violence or content that encourages self-harm, exploitation or dangerous acts. Sexual content involving minors, grooming and child exploitation are strictly prohibited. Do not use Nana to arrange illegal activity."),
        ("Respect personal boundaries", "Ask before recording or sharing someone’s voice, image or conversation. Never publish private messages, addresses, phone numbers, financial details or another person’s location without permission. Respect a refusal and do not bypass a block with another account."),
        ("Host with care", "Use a clear room title and category. Give people space to speak, avoid disruptive noise and do not pressure anyone to turn on a microphone or camera. Room descriptions, music requests, chat messages and gift messages follow these same rules."),
        ("Share what you have permission to share", "Use your own photos, videos and music, or content you are authorized to share. Do not rebroadcast copyrighted performances or impersonate artists, other members or Nana staff. Credit alone does not replace permission."),
        ("Keep gifts voluntary", "Never pressure someone to buy coins or send a gift. Do not promise money, affection, access or prizes in exchange for gifts. No scams, gambling, paid sexual services or off-platform payment requests. Never ask for passwords, verification codes or payment-card details."),
        ("Be honest and avoid spam", "Do not use misleading profiles, fake giveaways, automated messages, repeated promotions or manipulated engagement. Do not present a recording as a live interaction or use someone else’s identity to mislead the community."),
        ("Use safety tools responsibly", "Use the Report or Block controls on the relevant profile, room or post. Describe what happened clearly and avoid false or retaliatory reports. Blocking hides that person’s content for this account on this device. You can reverse a block in Settings → Blocked accounts."),
        ("Know what happens next", "These rules apply to profiles, posts, live video, voice rooms, private conversations and gifts. Violations may lead to content removal, feature restrictions or account removal when reviewed by the service. Serious or repeated abuse is not welcome. Nana is not an emergency service; contact local emergency services if someone is in immediate danger.")
    ]
    var body: some View {
        NanaSettingsDetailPage(title: "Community Guidelines", artwork: "NanaSettingsSecurity", headline: "Good conversations start with care", detail: "A shared standard for every room and every member. Updated September 23, 2026.") {
            ForEach(rules.indices, id: \.self) { index in
                NanaSettingsCard {
                    Text(String(format: "%02d", index + 1)).font(.caption.weight(.semibold)).foregroundStyle(NanaPalette.electricLilac)
                    Text(rules[index].0).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(rules[index].1).font(.subheadline).foregroundStyle(NanaPalette.mutedWhite)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            }
            NanaSettingsCard {
                Text("About reports in this version").font(.headline)
                Text("Reports are currently saved on this device; a saved report is not confirmation that a moderation team received it. You can block someone or leave a room immediately.")
                    .font(.footnote).foregroundStyle(NanaPalette.mutedWhite)
                NanaSettingsImageButton(title: "Manage blocked accounts") { showingBlacklist = true }
            }
        }
        .fullScreenCover(isPresented: $showingBlacklist) { NanaBlacklistView() }
    }
}
