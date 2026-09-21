import SwiftUI

struct WaterlineWelcomeView: View {
    @EnvironmentObject private var mockStore: NanaMockStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var isLoading = true
    @State private var showingSearch = false
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedPost: NanaPost?
    @State private var selectedProfile: NanaProfile?

    private var visibleRooms: [NanaLiveRoom] {
        mockStore.filteredRooms(for: mockStore.searchFilter).filter { room in
            switch mockStore.selectedCategory {
            case "Following": return room.isFollowingHost
            case "For you": return true
            default: return room.category == mockStore.selectedCategory
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop(imageName: "NanaLiveBackdrop")
                if isLoading {
                    NanaScreenLoading(label: "Tuning the room")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 23) {
                            header
                            categoryRail
                            if let feature = visibleRooms.first {
                                featureRoom(feature)
                            }
                            NanaSectionTitle(eyebrow: "Live feeds", title: "Find a room that fits")
                            if mockStore.payload.rooms.isEmpty {
                                NanaErrorState(title: "The room feed is unavailable", detail: "The local source could not provide the starting rooms.", actionTitle: "Retry") {
                                    mockStore.resetLocalMock()
                                }
                            } else if visibleRooms.isEmpty {
                                NanaEmptyState(title: "No rooms in this rhythm", detail: "Try another category or search for a room.", actionTitle: "Show all") {
                                    mockStore.selectedCategory = "For you"
                                }
                            } else {
                                ForEach(visibleRooms.dropFirst()) { room in
                                    Button { selectedRoom = room } label: {
                                        roomRow(room)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            NanaSectionTitle(eyebrow: "The community", title: "A question worth opening")
                            ForEach(mockStore.payload.posts) { post in
                                Button { selectedPost = post } label: { postCard(post) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, NanaPalette.screenPadding)
                        .padding(.top, 18)
                        .padding(.bottom, 110)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard isLoading else { return }
                try? await Task.sleep(for: .milliseconds(350))
                isLoading = false
            }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
            .sheet(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
            .sheet(item: $selectedPost) { post in NanaPostDetailView(post: post) }
            .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LIVE FEEDS")
                    .font(NanaType.stamp)
                    .tracking(1.5)
                    .foregroundStyle(NanaPalette.softPink)
                Text("Good evening, \(sessionStore.activeProfile?.displayName.split(separator: " ").first.map(String.init) ?? "friend")")
                    .font(NanaType.hero)
                    .foregroundStyle(NanaPalette.warmWhite)
                Text("Pick a room and stay for a while.")
                    .font(NanaType.body)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            Button { showingSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(NanaPalette.cardStrong, in: Circle())
                    .overlay(Circle().stroke(NanaPalette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mockStore.categories, id: \.self) { category in
                    NanaChip(title: category, isSelected: mockStore.selectedCategory == category) {
                        mockStore.selectedCategory = category
                    }
                }
            }
        }
    }

    private func featureRoom(_ room: NanaLiveRoom) -> some View {
        Button { selectedRoom = room } label: {
            VStack(alignment: .leading, spacing: 0) {
                NanaRoomArtwork(room: room, height: 220)
                HStack(spacing: 11) {
                    NanaPlaceholderPortrait(title: room.hostName, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.hostName)
                            .font(NanaType.bodyMedium)
                            .foregroundStyle(NanaPalette.warmWhite)
                        Text("\(room.category) · \(room.seatCapacity) seats")
                            .font(NanaType.caption)
                            .foregroundStyle(NanaPalette.mutedWhite)
                    }
                    Spacer()
                    Text("Enter")
                        .font(NanaType.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(NanaPalette.violet, in: Capsule())
                }
                .padding(13)
            }
            .nanaCard()
        }
        .buttonStyle(.plain)
    }

    private func roomRow(_ room: NanaLiveRoom) -> some View {
        HStack(spacing: 12) {
            NanaRoomArtwork(room: room, height: 93)
                .frame(width: 132)
            VStack(alignment: .leading, spacing: 7) {
                Text(room.title)
                    .font(NanaType.bodyMedium)
                    .foregroundStyle(NanaPalette.warmWhite)
                    .lineLimit(2)
                Text(room.subtitle)
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Circle().fill(NanaPalette.neonPink).frame(width: 6, height: 6)
                    Text("\(room.viewerCount) listening")
                        .font(NanaType.caption)
                        .foregroundStyle(NanaPalette.mutedWhite)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .nanaCard()
    }

    private func postCard(_ post: NanaPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(post.category.uppercased())
                    .font(NanaType.stamp)
                    .tracking(1)
                    .foregroundStyle(NanaPalette.softPink)
                Spacer()
                Text(post.publishedLabel)
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            Text(post.title)
                .font(NanaType.section)
                .foregroundStyle(NanaPalette.warmWhite)
            Text(post.body)
                .font(NanaType.body)
                .foregroundStyle(NanaPalette.mutedWhite)
                .lineLimit(3)
            HStack {
                Text(post.authorName)
                    .font(NanaType.caption.weight(.semibold))
                    .foregroundStyle(NanaPalette.electricLilac)
                Spacer()
                Label("\(post.commentCount)", systemImage: "bubble.left")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
        }
        .padding(16)
        .nanaCard()
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
            Text(label)
                .font(NanaType.caption.weight(.semibold))
                .foregroundStyle(NanaPalette.mutedWhite)
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
            Image(systemName: "sparkles.tv")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(NanaPalette.electricLilac)
            Text(title)
                .font(NanaType.bodyMedium)
                .foregroundStyle(NanaPalette.warmWhite)
            Text(detail)
                .font(NanaType.caption)
                .foregroundStyle(NanaPalette.mutedWhite)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(NanaPrimaryButtonStyle())
                    .padding(.top, 5)
            }
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
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(NanaPalette.softPink)
            Text(title)
                .font(NanaType.bodyMedium)
                .foregroundStyle(NanaPalette.warmWhite)
            Text(detail)
                .font(NanaType.caption)
                .foregroundStyle(NanaPalette.mutedWhite)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.neonPink))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .nanaCard()
    }
}
