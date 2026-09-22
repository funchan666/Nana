import SwiftUI

struct HarborGatheringView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingCreateRoom = false
    @State private var showingSearch = false
    @State private var showingRanking = false
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedCategory = "Category"

    private var roomCategories: [String] { ["Category", "Following", "Late night", "Creative", "Music", "Open talk"] }

    private var rooms: [NanaLiveRoom] {
        let source = contentStore.filteredRooms(for: contentStore.searchFilter)
        switch selectedCategory {
        case "Category": return source
        case "Following": return source.filter(\.isFollowingHost)
        default: return source.filter { $0.category == selectedCategory }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                if contentStore.payload.rooms.isEmpty && contentStore.state(for: .rooms) == .loading {
                    NanaScreenLoading(label: "Opening rooms")
                } else if contentStore.payload.rooms.isEmpty, case .failed(let error) = contentStore.state(for: .rooms) {
                    NanaErrorState(title: "Rooms are unavailable", detail: error.localizedDescription, actionTitle: "Retry") {
                        Task { await contentStore.refresh(.rooms) }
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                } else if rooms.isEmpty {
                    NanaEmptyState(title: "No rooms in this category", detail: "Try another category or open a new room.", actionTitle: "Create a room") {
                        showingCreateRoom = true
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            voiceHeader
                            roomSearch
                            categoryRail
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                                ForEach(rooms) { room in
                                    Button { selectedRoom = room } label: {
                                        NanaVoiceRoomCard(
                                            room: room,
                                            profiles: contentStore.payload.profiles,
                                            seats: contentStore.payload.roomSeats,
                                            blockedProfileIDs: contentStore.blockedProfileIDs
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 9)
                        .padding(.bottom, 116)
                    }
                    .refreshable { await contentStore.refresh(.rooms) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await contentStore.refresh(.rooms) }
            .sheet(isPresented: $showingCreateRoom) { NanaCreateRoomView() }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
            .fullScreenCover(isPresented: $showingRanking) { NanaRankingView() }
            .fullScreenCover(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
        }
    }

    private var voiceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Voice Rooms")
                .font(.system(size: 19, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            Spacer()
            Button { showingRanking = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_055", contentMode: .fit)
                    .frame(width: 40, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ranking")
            Button { showingCreateRoom = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_158", contentMode: .fit)
                    .frame(width: 88, height: 34)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create a room")
        }
    }

    private var roomSearch: some View {
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
            .background(NanaPalette.deepSpace.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(NanaPalette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var categoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(roomCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                        contentStore.selectedCategory = category == "Category" ? "For you" : category
                    } label: {
                        Text(category)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selectedCategory == category ? .white : NanaPalette.mutedWhite)
                            .padding(.horizontal, 13)
                            .frame(height: 20)
                            .background(
                                selectedCategory == category
                                    ? Color(red: 0.30, green: 0.26, blue: 0.51)
                                    : Color(red: 0.14, green: 0.13, blue: 0.17),
                                in: Capsule()
                            )
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct NanaVoiceRoomCard: View {
    let room: NanaLiveRoom
    let profiles: [NanaProfile]
    let seats: [NanaRoomSeat]
    let blockedProfileIDs: Set<String>

    // Cover artwork is separate from the live seat roster. Supplementary photos
    // decorate the room card only; they never create members or change its count.
    private static let coverPhotoKeys = [
        "nana.pic.Dc6OjcqAodc", "nana.pic.DdJ2uSSDENz",
        "nana.pic.DczCXb6HMNj", "nana.pic.DdTY1ZoDJ_o",
        "nana.pic.DdMJA6mE7N0", "nana.pic.DdQxT9NCkQ1",
        "nana.pic.Dc0SA4UiUy3", "nana.pic.Dc0XoT9DgeO",
        "nana.pic.Dc1CvDfCCHN", "nana.pic.Dc1Ii5HACCq",
        "nana.pic.DdTmQsaCOiK", "nana.pic.DdV5vxnEs3N"
    ]

    private var coverPhotoCount: Int {
        switch room.seatCapacity {
        case ...3: return 4
        case 4...6: return 6
        default: return 9
        }
    }

    private var coverPhotos: [String] {
        let blockedAssets = Set(profiles.filter { blockedProfileIDs.contains($0.id) }.compactMap(\.avatarAssetKey))
        var result: [String] = []
        var included: Set<String> = []
        func appendPhoto(_ key: String?) {
            guard let key, !blockedAssets.contains(key), included.insert(key).inserted,
                  NanaAssetLibrary.image(for: key) != nil else { return }
            result.append(key)
        }
        if !blockedProfileIDs.contains(room.hostID) { appendPhoto(room.hostAvatarAssetKey) }
        for seat in seats.filter({ $0.roomID == room.id }).sorted(by: { $0.position < $1.position }) {
            guard let id = seat.profileID, !blockedProfileIDs.contains(id) else { continue }
            appendPhoto(profiles.first { $0.id == id }?.avatarAssetKey)
        }
        // Stable across launches, refreshes and filtering; Swift's hashValue is not.
        var seed = room.id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        var pool = Self.coverPhotoKeys
        for index in stride(from: pool.count - 1, through: 1, by: -1) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            pool.swapAt(index, Int((seed >> 32) % UInt64(index + 1)))
        }
        for key in pool {
            if result.count >= coverPhotoCount { break }
            appendPhoto(key)
        }
        return Array(result.prefix(coverPhotoCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_024", contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .accessibilityHidden(true)
                Text("Voice")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(red: 0.55, green: 0.84, blue: 0.54))
                Spacer(minLength: 0)
                Label("\(room.viewerCount)", systemImage: "person.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(.black.opacity(0.35), in: Capsule())
            }
            .padding(.leading, 7)

            coverCollage

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        roomTag("Voice", color: Color(red: 0.95, green: 0.70, blue: 0.99))
                        roomTag(room.category, color: Color(red: 0.77, green: 0.70, blue: 0.99))
                    }
                }
                Spacer(minLength: 0)
                NanaAssetImage(assetKey: "nana.voice.voice_asset_041", contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            Text(room.subtitle)
                .font(.system(size: 9))
                .foregroundStyle(NanaPalette.mutedWhite)
                .lineLimit(1)
        }
        .padding(8)
        .background(Color(red: 0.075, green: 0.055, blue: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NanaPalette.border, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_016", contentMode: .fit)
                .frame(width: 28, height: 30)
                .offset(x: -2, y: -2)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private var coverCollage: some View {
        let photos = coverPhotos
        let columns = photos.count <= 4 ? 2 : 3
        let rows = max(1, (photos.count + columns - 1) / columns)
        return GeometryReader { geometry in
            let spacing: CGFloat = 2
            let tileWidth = max(0, (geometry.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
            let tileHeight = max(0, (geometry.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows))
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < photos.count {
                                NanaAssetImage(assetKey: photos[index])
                                    .frame(width: tileWidth, height: tileHeight)
                                    .clipped()
                            } else {
                                Color.clear.frame(width: tileWidth, height: tileHeight)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(3)
        .background(NanaPalette.violet.opacity(0.20), in: RoundedRectangle(cornerRadius: 5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }

    private func roomTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Color(red: 0.47, green: 0.18, blue: 0.66))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(color, in: Capsule())
    }
}

private struct NanaCreateRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var roomName = ""
    @State private var roomTopic = ""
    @State private var seatCapacity = 6
    @State private var selectedCategory = "Open talk"
    @State private var isPublic = true

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop(imageName: "nana.voice.room_backdrop_01")
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 35, height: 35)
                                    .background(.black.opacity(0.25), in: Circle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text("Voice room")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Color.clear.frame(width: 35, height: 35)
                        }
                        .padding(.bottom, 4)

                        Text("Create a room")
                            .font(NanaType.hero)
                            .foregroundStyle(NanaPalette.warmWhite)
                        Text("Set a small stage for the next conversation.")
                            .font(NanaType.body)
                            .foregroundStyle(NanaPalette.mutedWhite)

                        roomField(title: "Room theme", placeholder: "Please enter the room theme", text: $roomName)
                        roomField(title: "Room content", placeholder: "Please enter the room information", text: $roomTopic)

                        HStack {
                            Text("Make this room public")
                                .font(NanaType.bodyMedium)
                                .foregroundStyle(NanaPalette.warmWhite)
                            Spacer()
                            Toggle("", isOn: $isPublic)
                                .labelsHidden()
                                .tint(NanaPalette.violet)
                        }
                        .padding(13)
                        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Microphones")
                                .font(NanaType.caption.weight(.semibold))
                                .foregroundStyle(NanaPalette.mutedWhite)
                            HStack(spacing: 7) {
                                ForEach([3, 6, 9, 12], id: \.self) { capacity in
                                    Button { seatCapacity = capacity } label: {
                                        Text("\(capacity)")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(seatCapacity == capacity ? .white : NanaPalette.mutedWhite)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(seatCapacity == capacity ? NanaPalette.violet : NanaPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NanaPalette.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Select label")
                                .font(NanaType.caption.weight(.semibold))
                                .foregroundStyle(NanaPalette.mutedWhite)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(["Music", "Open talk", "Creative", "Late night"], id: \.self) { label in
                                        NanaChip(title: label, isSelected: selectedCategory == label) { selectedCategory = label }
                                    }
                                }
                            }
                        }

                        Button {
                            guard !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            contentStore.explainUnavailable("Creating rooms")
                        } label: {
                            Text("Create a room")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NanaPrimaryButtonStyle())
                        .padding(.top, 5)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 15)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func roomField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(NanaType.caption.weight(.semibold))
                .foregroundStyle(NanaPalette.mutedWhite)
            TextField(placeholder, text: text)
                .foregroundStyle(.white)
                .nanaGlassField()
        }
    }
}
