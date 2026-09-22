import SwiftUI

struct WaterlineWelcomeView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var isLoading = true
    @State private var showingSearch = false
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedHomeCategory = "Category"
    @State private var feedMode = "Recommend"

    private let homeCategories = ["Category", "Following", "Late night", "Creative", "Music", "Open talk"]

    private var filteredRooms: [NanaLiveRoom] {
        let rooms = feedMode == "Follow"
            ? contentStore.filteredRooms(for: contentStore.searchFilter).filter(\.isFollowingHost)
            : contentStore.filteredRooms(for: contentStore.searchFilter)
        switch selectedHomeCategory {
        case "Following": return rooms.filter(\.isFollowingHost)
        case "Category": return rooms
        default: return rooms.filter { $0.category == selectedHomeCategory }
        }
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

                if isLoading || contentStore.state(for: .homeFeed) == .loading {
                    NanaScreenLoading(label: "Tuning the room")
                } else if case .failed(let error) = contentStore.state(for: .homeFeed), !contentStore.hasContent(for: .homeFeed) {
                    NanaErrorState(title: "The room feed is unavailable", detail: error.localizedDescription, actionTitle: "Retry") {
                        Task { await contentStore.refresh(.homeFeed) }
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                } else if filteredRooms.isEmpty {
                    NanaEmptyState(title: "No rooms in this rhythm", detail: "Try another category or search for a room.", actionTitle: "Show all") {
                        selectedHomeCategory = "Category"
                        contentStore.selectedCategory = "For you"
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            homeHeader
                            discoverySearch
                            if let leadRoom = filteredRooms.first {
                                leadRoomCard(leadRoom)
                                creatorRail(leadRoom: leadRoom)
                            }
                            categoryRail
                            liveGrid
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
            .sheet(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Live Feeds")
                .font(.system(size: 19, weight: .bold, design: .serif).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            Spacer(minLength: 8)
            Button { contentStore.explainUnavailable("Starting a live room") } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Live").font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(NanaPalette.violet, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { contentStore.explainUnavailable("Opening the room deck") } label: {
                Group {
                    if let camera = NanaAssetLibrary.image(for: "nana.photo.photo_placeholder_01") {
                        Image(uiImage: camera).resizable().scaledToFit().padding(7)
                    } else {
                        Image(systemName: "rectangle.stack.fill").font(.system(size: 15, weight: .semibold))
                    }
                }
                    .foregroundStyle(NanaPalette.softPink)
                    .frame(width: 33, height: 32)
                    .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(NanaPalette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
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

    private func leadRoomCard(_ room: NanaLiveRoom) -> some View {
        Button { selectedRoom = room } label: {
            ZStack(alignment: .topLeading) {
                NanaMediaPreview(assetKey: room.streamAssetKey ?? "nana.pic.DdTmQsaCOiK")
                    .frame(maxWidth: .infinity)
                    .frame(height: 188)
                    .clipped()
                    .allowsHitTesting(false)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.02), NanaPalette.midnight.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 5) {
                    Text("HOT").font(.system(size: 9, weight: .black, design: .rounded))
                    Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(NanaPalette.neonPink, in: Capsule())
                .padding(10)
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill").font(.system(size: 10, weight: .semibold))
                    Text("\(room.viewerCount)").font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(.black.opacity(0.38), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(10)
                VStack(alignment: .leading, spacing: 7) {
                    Spacer()
                    HStack(spacing: 7) {
                        NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.hostName).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Lv.\(max(room.seatCapacity, 1) + 22) · \(room.category)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Text("LIVE").font(.system(size: 9, weight: .black, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 7).frame(height: 20).background(NanaPalette.neonPink.opacity(0.9), in: Capsule())
                    }
                    Text(room.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 5) {
                        ForEach([room.category, "Mind", "Comedy"], id: \.self) { tag in
                            Text(tag).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(NanaPalette.warmWhite).padding(.horizontal, 8).frame(height: 18).background(NanaPalette.violet.opacity(0.74), in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "video.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(NanaPalette.softPink)
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
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Encountering Creativity").font(.system(size: 15, weight: .bold, design: .serif).italic()).foregroundStyle(NanaPalette.warmWhite)
                    Text("100, \(max(696, creators.count * 174)) Creators").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer()
                HStack(spacing: -9) {
                    ForEach(creators) { creator in NanaAvatarView(title: creator.displayName, assetKey: creator.avatarAssetKey, size: 31) }
                }
                .padding(.leading, 9)
                Button { selectedRoom = leadRoom } label: {
                    Text("Enter").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 30).background(NanaPalette.violet, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 22) {
                feedModeButton("Recommend")
                feedModeButton("Follow")
            }
        }
    }

    private func feedModeButton(_ title: String) -> some View {
        Button { feedMode = title } label: {
            VStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .bold, design: .serif).italic()).foregroundStyle(feedMode == title ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
                Capsule().fill(feedMode == title ? NanaPalette.neonPink : .clear).frame(width: 29, height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var categoryRail: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Category").font(.system(size: 12, weight: .bold, design: .serif).italic()).foregroundStyle(NanaPalette.warmWhite)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(homeCategories, id: \.self) { category in
                        Button {
                            selectedHomeCategory = category
                            contentStore.selectedCategory = category == "Category" ? "For you" : category
                        } label: {
                            Text(category).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(selectedHomeCategory == category ? .white : NanaPalette.mutedWhite).padding(.horizontal, 12).frame(height: 26).background(selectedHomeCategory == category ? NanaPalette.violet : NanaPalette.card, in: Capsule()).overlay(Capsule().stroke(selectedHomeCategory == category ? NanaPalette.violet : NanaPalette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var liveGrid: some View {
        let grid = Array(filteredRooms.dropFirst())
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 11) {
            ForEach(grid) { room in
                Button { selectedRoom = room } label: { NanaHomeRoomCard(room: room) }.buttonStyle(.plain)
            }
        }
    }
}

private struct NanaHomeRoomCard: View {
    let room: NanaLiveRoom

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NanaMediaPreview(assetKey: room.streamAssetKey ?? "nana.pic.DdV5vxnEs3N")
                .frame(maxWidth: .infinity)
                .frame(height: 174)
                .clipped()
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text("HOT").font(.system(size: 8, weight: .black, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 5).frame(height: 16).background(NanaPalette.neonPink, in: Capsule())
                    Spacer()
                    Text("\(room.viewerCount)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 5).frame(height: 16).background(.black.opacity(0.42), in: Capsule())
                }
                Spacer(minLength: 20)
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text(room.hostName).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Image(systemName: "video.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(NanaPalette.softPink)
                }
                Text("\(room.category) · \(room.roomState)").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            .padding(9)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 174)
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
