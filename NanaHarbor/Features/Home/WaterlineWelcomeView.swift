import SwiftUI

struct WaterlineWelcomeView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var isLoading = true
    @State private var showingSearch = false
    @State private var showingRanking = false
    @State private var showingLiveCreation = false
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedVideo: NanaBundledVideo?
    @State private var selectedHomeCategory = "All"
    @State private var feedMode = "Recommend"
    @State private var featuredRoomID = ""

    private let homeCategories = ["All", "Chat", "Music", "Creative", "Late night"]

    private var featuredRooms: [NanaLiveRoom] {
        contentStore.filteredRooms(for: contentStore.searchFilter)
    }

    private var featuredRoom: NanaLiveRoom? { featuredRooms.first }

    private var filteredRooms: [NanaLiveRoom] {
        let rooms = feedMode == "Follow"
            ? contentStore.filteredRooms(for: contentStore.searchFilter).filter(\.isFollowingHost)
            : contentStore.filteredRooms(for: contentStore.searchFilter)
        switch selectedHomeCategory {
        case "All": return rooms
        case "Chat": return rooms.filter { $0.category == "Open talk" }
        default: return rooms.filter { $0.category == selectedHomeCategory }
        }
    }

    private var additionalVideos: [NanaBundledVideo] {
        guard feedMode == "Recommend", selectedHomeCategory == "All" else { return [] }
        // A room's existing video keeps its position. Do not duplicate it, or reintroduce
        // videos belonging to blocked profiles through the bundled collection.
        let represented = Set(contentStore.payload.rooms.compactMap(\.streamAssetKey))
        return NanaAssetLibrary.videoClips.filter { !represented.contains($0.assetKey) }
    }

    private var hasVisibleContent: Bool { !filteredRooms.isEmpty || !additionalVideos.isEmpty }

    private func openRoomVideo(_ room: NanaLiveRoom) {
        selectedRoom = room
    }

    private var creators: [NanaProfile] {
        let profiles = contentStore.payload.profiles
        if !profiles.isEmpty { return Array(profiles.prefix(4)) }
        return filteredRooms.prefix(4).map {
            NanaProfile(id: $0.hostID, displayName: $0.hostName, handle: $0.hostName.lowercased().replacingOccurrences(of: " ", with: "."), region: "", language: "", gender: "", age: 0, introduction: "", avatarAssetKey: $0.hostAvatarAssetKey, isConnected: false, followerCount: 0, followingCount: 0, level: 0)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()

                if (isLoading || contentStore.state(for: .homeFeed) == .loading) && !hasVisibleContent {
                    NanaScreenLoading(label: "Tuning the room")
                } else if case .failed(let error) = contentStore.state(for: .homeFeed), !contentStore.hasContent(for: .homeFeed), !hasVisibleContent {
                    NanaErrorState(title: "The room feed is unavailable", detail: error.localizedDescription, actionTitle: "Retry") {
                        Task { await contentStore.refresh(.homeFeed) }
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            homeHeader
                            discoverySearch
                            if case .failed = contentStore.state(for: .homeFeed) {
                                HStack {
                                    Text("Rooms couldn't refresh. Videos are available.")
                                        .font(NanaType.caption)
                                        .foregroundStyle(NanaPalette.mutedWhite)
                                    Spacer()
                                    Button("Retry") { Task { await contentStore.refresh(.homeFeed) } }
                                        .font(NanaType.caption.weight(.semibold))
                                        .foregroundStyle(NanaPalette.electricLilac)
                                        .frame(minHeight: 44)
                                }
                            }
                            if let leadRoom = featuredRoom {
                                featuredRoomCarousel
                                creatorRail(leadRoom: leadRoom)
                            }
                            feedSection
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 9)
                        .padding(.bottom, 116)
                    }
                    .refreshable { await contentStore.refresh(.homeFeed) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await contentStore.refresh(.homeFeed)
                guard isLoading else { return }
                try? await Task.sleep(for: .milliseconds(350))
                isLoading = false
            }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
            .fullScreenCover(isPresented: $showingLiveCreation) { NanaLiveCreationView() }
            .fullScreenCover(isPresented: $showingRanking) { NanaRankingView() }
            .fullScreenCover(item: $selectedRoom) { room in NanaLiveRoomView(room: room) }
            .fullScreenCover(item: $selectedVideo) { clip in NanaVideoPlayerView(clip: clip) }
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Live Feeds")
                .font(.system(size: 19, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            Spacer(minLength: 8)
            Button { showingRanking = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_055", contentMode: .fit)
                    .frame(width: 40, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ranking")
            .accessibilityHint("Open the ranking list")
            Button { showingLiveCreation = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_054", contentMode: .fit)
                    .frame(width: 70, height: 34)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start a live room")
        }
    }

    private var discoverySearch: some View {
        Button { showingSearch = true } label: {
            HStack(spacing: 9) {
                Text("Please enter search content")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(NanaPalette.mutedWhite)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NanaPalette.warmWhite)
            }
            .padding(.horizontal, 14)
            .frame(height: 37)
            .background(NanaPalette.deepSpace.opacity(0.68), in: Capsule())
            .overlay(Capsule().stroke(NanaPalette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var featuredRoomCarousel: some View {
        let rooms = featuredRooms
        let selectedIndex = rooms.firstIndex { $0.id == featuredRoomID } ?? 0
        return VStack(spacing: 8) {
            TabView(selection: $featuredRoomID) {
                ForEach(rooms) { room in
                    leadRoomCard(room)
                        .frame(height: 188)
                        .tag(room.id)
                        .accessibilityLabel("\(room.hostName), \(room.title)")
                        .accessibilityHint("Open this room. Swipe left or right for more rooms.")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 188)
            .accessibilityValue("Room \(selectedIndex + 1) of \(rooms.count)")

            if rooms.count > 1 {
                HStack(spacing: 5) {
                    ForEach(rooms) { room in
                        Capsule()
                            .fill(room.id == featuredRoomID ? NanaPalette.violet : Color.white.opacity(0.3))
                            .frame(width: room.id == featuredRoomID ? 18 : 5, height: 4)
                    }
                }
                .frame(height: 8)
                .animation(.easeInOut(duration: 0.18), value: featuredRoomID)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: rooms.map(\.id), initial: true) { _, ids in
            // Keep the visible room stable after refresh; reset only if it disappeared.
            if !ids.contains(featuredRoomID) { featuredRoomID = ids.first ?? "" }
        }
    }

    private func leadRoomCard(_ room: NanaLiveRoom) -> some View {
        Button { openRoomVideo(room) } label: {
            ZStack(alignment: .topLeading) {
                NanaMediaPreview(assetKey: room.streamAssetKey ?? "nana.pic.DdTmQsaCOiK")
                    .frame(maxWidth: .infinity)
                    .frame(height: 188)
                    .clipped()
                    .allowsHitTesting(false)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.02), NanaPalette.midnight.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                NanaAssetImage(assetKey: "nana.voice.voice_asset_016", contentMode: .fit)
                    .frame(width: 34, height: 36)
                    .accessibilityHidden(true)
                HStack(spacing: 5) {
                    Label("\(room.viewerCount)", systemImage: "person.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(.black.opacity(0.38), in: Capsule())
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                        .frame(width: 37, height: 15)
                        .accessibilityLabel("Live")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(8)
                VStack(alignment: .leading, spacing: 7) {
                    Spacer()
                    HStack(spacing: 7) {
                        NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.hostName).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Lv.\(max(room.seatCapacity, 1) + 22) · \(room.category)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                    }
                    Text(room.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 5) {
                        ForEach([room.category, "Mind", "Comedy"], id: \.self) { tag in
                            Text(tag).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(NanaPalette.warmWhite).padding(.horizontal, 8).frame(height: 18).background(NanaPalette.violet.opacity(0.74), in: Capsule())
                        }
                        Spacer()
                        NanaHomeVideoActionArtwork()
                    }
                }
                .padding(13)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func creatorRail(leadRoom: NanaLiveRoom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Encountering Creativity")
                .font(.system(size: 14, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(creators.count) Creators")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NanaPalette.warmWhite)
                    Text("Enter the creator chat")
                        .font(.system(size: 10))
                        .foregroundStyle(NanaPalette.mutedWhite)
                    Button { selectedRoom = leadRoom } label: {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_056", contentMode: .fit)
                            .frame(width: 86, height: 32)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enter creator room")
                }
                Spacer(minLength: 0)
                HStack(spacing: -10) {
                    ForEach(creators) { creator in
                        NanaAvatarView(title: creator.displayName, assetKey: creator.avatarAssetKey, size: 35)
                    }
                }
            }
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 24) {
                feedModeButton("Recommend")
                feedModeButton("Follow")
            }
            categoryRail
            if hasVisibleContent {
                liveGrid.padding(.top, 4)
            } else {
                NanaEmptyState(
                    title: feedMode == "Follow" ? "No followed rooms here yet" : "No rooms in this category",
                    detail: "Choose another category to keep exploring.",
                    actionTitle: "Show all"
                ) {
                    selectedHomeCategory = "All"
                    feedMode = "Recommend"
                    contentStore.searchFilter = NanaSearchFilter()
                    contentStore.selectedCategory = "For you"
                }
                .padding(.top, 8)
            }
        }
    }

    private func feedModeButton(_ title: String) -> some View {
        Button { feedMode = title } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy).italic())
                    .lineLimit(1)
                    .frame(height: 20)
                    .foregroundStyle(feedMode == title ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
                Capsule().fill(feedMode == title ? NanaPalette.violet : .clear)
                    .frame(width: 20, height: 3)
            }
            .frame(width: 96, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(feedMode == title ? [.isSelected] : [])
    }

    private var categoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(homeCategories, id: \.self) { category in
                    Button {
                        selectedHomeCategory = category
                        contentStore.selectedCategory = category == "All" ? "For you" : (category == "Chat" ? "Open talk" : category)
                    } label: {
                        Text(category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedHomeCategory == category ? .white : NanaPalette.mutedWhite)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(
                                selectedHomeCategory == category
                                    ? Color(red: 0.30, green: 0.26, blue: 0.51)
                                    : Color(red: 0.14, green: 0.13, blue: 0.17),
                                in: Capsule()
                            )
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedHomeCategory == category ? [.isSelected] : [])
                }
            }
        }
        .frame(height: 44)
    }

    private var liveGrid: some View {
        // Keep filtered matches in the list, even when there is only one result.
        let grid = selectedHomeCategory == "All" && feedMode == "Recommend"
            ? filteredRooms.filter { $0.id != featuredRoom?.id }
            : filteredRooms
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 169, maximum: 169), spacing: 9)], spacing: 11) {
            ForEach(grid) { room in
                Button { openRoomVideo(room) } label: { NanaHomeRoomCard(room: room) }.buttonStyle(.plain)
            }
            ForEach(additionalVideos) { clip in
                Button { selectedVideo = clip } label: { NanaHomeVideoCard(clip: clip) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play video from \(clip.creatorLabel)")
            }
        }
    }
}

/// The exported artwork already includes the dimensional camera and play glyph.
private struct NanaHomeVideoActionArtwork: View {
    var body: some View {
        NanaAssetImage(assetKey: "nana.voice.voice_asset_011", contentMode: .fit)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

private struct NanaHomeVideoCard: View {
    let clip: NanaBundledVideo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NanaMediaPreview(assetKey: clip.assetKey)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("VIDEO")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(NanaPalette.violet, in: Capsule())
                    Spacer()
                }
                Spacer()
                HStack(spacing: 5) {
                    Text(clip.creatorLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    NanaHomeVideoActionArtwork()
                }
                Text("Watch video")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(9)
        }
        .frame(width: 169, height: 227)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct NanaHomeRoomCard: View {
    let room: NanaLiveRoom

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NanaMediaPreview(assetKey: room.streamAssetKey ?? "nana.pic.DdV5vxnEs3N")
                .frame(width: 169, height: 227)
                .clipped()
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Label("\(room.viewerCount)", systemImage: "person.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(.black.opacity(0.38), in: Capsule())
                    Spacer()
                    if ["live", "live now"].contains(room.roomState.lowercased()) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                            .frame(width: 37, height: 15)
                            .accessibilityLabel("Live")
                    }
                }
                Spacer(minLength: 20)
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text(room.hostName).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    NanaHomeVideoActionArtwork()
                }
                Text("\(room.category) · \(room.roomState)").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            .padding(9)
        }
        .frame(width: 169, height: 227)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

struct NanaScreenLoading: View {
    let label: String
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(NanaPalette.violet.opacity(0.3), lineWidth: 2).frame(width: 52, height: 52)
                Circle().trim(from: 0.1, to: 0.38).stroke(NanaPalette.neonPink, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 52, height: 52).rotationEffect(.degrees(pulse ? 360 : 0))
            }
            Text(label).font(NanaType.caption.weight(.semibold)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

struct NanaEmptyState: View {
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "sparkles.tv").font(.system(size: 28, weight: .light)).foregroundStyle(NanaPalette.electricLilac)
            Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
            Text(detail).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(NanaPrimaryButtonStyle()).padding(.top, 5) }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .nanaCard()
    }
}

struct NanaErrorState: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 27, weight: .light)).foregroundStyle(NanaPalette.softPink)
            Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
            Text(detail).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center)
            Button(actionTitle, action: action).buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.neonPink)).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .nanaCard()
    }
}
