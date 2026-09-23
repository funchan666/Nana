import SwiftUI

struct HarborGatheringView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingCreateRoom = false
    @State private var showingSearch = false
    @State private var showingRanking = false
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedCategory = "All"

    // The voice directory has its own filters; people/post searches elsewhere
    // must not empty its categories.
    private var availableRooms: [NanaLiveRoom] {
        contentStore.payload.rooms.filter { contentStore.isRoomVisible($0) }
    }

    private var roomCategories: [String] {
        ["All", "Following"] + NanaVoiceRoomTopics.categories(in: availableRooms)
    }

    private func rooms(in category: String) -> [NanaLiveRoom] {
        switch category {
        case "All": return availableRooms
        case "Following": return availableRooms.filter(\.isFollowingHost)
        default: return availableRooms.filter { NanaVoiceRoomTopics.category(for: $0) == category }
        }
    }

    private var rooms: [NanaLiveRoom] {
        rooms(in: selectedCategory)
    }

    private var categoryDescription: String {
        switch selectedCategory {
        case "All": return "Find a conversation to join"
        case "Following": return "Rooms from hosts you follow"
        case "Chat": return "Easy conversations, day or night"
        case "Music": return "Share songs and discover new sounds"
        case "Creative": return "Exchange ideas, stories and inspiration"
        default: return "Explore \(selectedCategory.lowercased()) conversations"
        }
    }

    var body: some View {
        // Allocate before category/search filtering so a portrait keeps its room.
        let roomCoverPhotos = NanaRoomPortraitAllocator.photosByRoom(
            rooms: contentStore.payload.rooms,
            profiles: contentStore.payload.profiles,
            seats: contentStore.payload.roomSeats,
            blockedProfileIDs: contentStore.hiddenAuthorIDs, excludedPhotoKeys: contentStore.hiddenPortraitAssetKeys
        )
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        voiceHeader
                        roomSearch
                        categoryRail
                        categorySummary
                        roomContent(coverPhotos: roomCoverPhotos)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 116)
                }
                .refreshable { await contentStore.refresh(.rooms) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await contentStore.refresh(.rooms) }
            .onChange(of: roomCategories) { _, categories in
                if !categories.contains(selectedCategory) { selectedCategory = "All" }
            }
            .fullScreenCover(isPresented: $showingCreateRoom) { NanaCreateRoomView() }
            .sheet(isPresented: $showingSearch) { NanaDiscoverySearchView() }
            .fullScreenCover(isPresented: $showingRanking) { NanaRankingView() }
            .fullScreenCover(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
        }
    }

    private var categorySummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(categoryDescription)
                .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            Spacer(minLength: 0)
            Text("\(rooms.count) \(rooms.count == 1 ? "room" : "rooms")")
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(NanaPalette.electricLilac).fixedSize()
        }
    }

    @ViewBuilder private func roomContent(coverPhotos: [String: [String]]) -> some View {
        if contentStore.payload.rooms.isEmpty && contentStore.state(for: .rooms) == .loading {
            NanaScreenLoading(label: "Opening rooms")
        } else if contentStore.payload.rooms.isEmpty, case .failed(let error) = contentStore.state(for: .rooms) {
            NanaErrorState(title: "Rooms are unavailable", detail: error.localizedDescription, actionTitle: "Retry") {
                Task { await contentStore.refresh(.rooms) }
            }
        } else if rooms.isEmpty {
            NanaEmptyState(
                title: selectedCategory == "Following" ? "Your people, your rooms" : "No rooms to explore yet",
                detail: selectedCategory == "Following"
                    ? "Follow a host you enjoy. Their rooms will appear here."
                    : "Check back for more conversations or start a room of your own.",
                actionTitle: selectedCategory == "Following" ? "Explore rooms" : "Create a room"
            ) {
                if selectedCategory == "Following" { selectedCategory = "All" }
                else { showingCreateRoom = true }
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(rooms) { room in
                    Button { selectedRoom = room } label: {
                        NanaVoiceRoomCard(room: room, coverPhotos: coverPhotos[room.id] ?? [])
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    } label: {
                        Text(category)
                            .font(.system(size: 12, weight: selectedCategory == category ? .semibold : .medium))
                            .foregroundStyle(selectedCategory == category ? .white : NanaPalette.mutedWhite)
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .background(
                                selectedCategory == category
                                    ? NanaPalette.violet
                                    : Color(red: 0.14, green: 0.13, blue: 0.17),
                                in: Capsule()
                            )
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category), \(rooms(in: category).count) rooms")
                    .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
                }
            }
        }
    }
}

/// Shared topic grouping for the directory and in-room recommendations.
enum NanaVoiceRoomTopics {
    static func category(for room: NanaLiveRoom) -> String {
        let category = room.category.trimmingCharacters(in: .whitespacesAndNewlines)
        switch category.lowercased() {
        case "open talk", "late night", "chat", "": return "Chat"
        case "music": return "Music"
        case "creative": return "Creative"
        default: return category
        }
    }

    static func categories(in rooms: [NanaLiveRoom]) -> [String] {
        let topics = Set(rooms.map { category(for: $0) })
        let preferred = ["Chat", "Music", "Creative"]
        return preferred.filter { topics.contains($0) } + topics.subtracting(Set(preferred)).sorted()
    }
}

struct NanaMoreVoiceRoomsView: View {
    let currentRoomID: String
    let selectRoom: (NanaLiveRoom) -> Void
    let close: () -> Void
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedCategory = "All"

    private var availableRooms: [NanaLiveRoom] {
        contentStore.payload.rooms.filter { $0.id != currentRoomID && contentStore.isRoomVisible($0) }
    }
    private var categories: [String] { ["All"] + NanaVoiceRoomTopics.categories(in: availableRooms) }
    private var visibleRooms: [NanaLiveRoom] {
        availableRooms.filter { selectedCategory == "All" || NanaVoiceRoomTopics.category(for: $0) == selectedCategory }
    }
    private var coverPhotos: [String: [String]] {
        NanaRoomPortraitAllocator.photosByRoom(
            rooms: contentStore.payload.rooms, profiles: contentStore.payload.profiles,
            seats: contentStore.payload.roomSeats, blockedProfileIDs: contentStore.hiddenAuthorIDs,
            excludedPhotoKeys: contentStore.hiddenPortraitAssetKeys
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            categoryPicker
            ScrollView(showsIndicators: false) {
                roomGrid
                    .padding(.top, 3).padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16).padding(.top, 12)
        .foregroundStyle(NanaPalette.warmWhite)
        .background {
            Color(red: 0.065, green: 0.052, blue: 0.075)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: categories) { _, updated in
            if !updated.contains(selectedCategory) { selectedCategory = "All" }
        }
        .accessibilityAction(.escape, close)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("More voice rooms").font(.system(size: 19, weight: .heavy).italic())
                    .accessibilityAddTraits(.isHeader)
                Text("\(visibleRooms.count) \(visibleRooms.count == 1 ? "room" : "rooms") to explore")
                    .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.07), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Close more voice rooms")
        }
    }

    private var categoryPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 4) {
            ForEach(categories, id: \.self) { category in
                Button { selectedCategory = category } label: {
                    Text(category).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(selectedCategory == category ? NanaPalette.violet : .white.opacity(0.08), in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder private var roomGrid: some View {
        if visibleRooms.isEmpty {
            Text("No other voice rooms are available right now.")
                .font(.system(size: 14)).foregroundStyle(NanaPalette.mutedWhite)
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 40)
        } else {
            let photos = coverPhotos
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(visibleRooms) { room in
                    Button { selectRoom(room) } label: {
                        NanaVoiceRoomCard(room: room, coverPhotos: photos[room.id] ?? [])
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Join \(room.title), \(room.category), hosted by \(room.hostName)")
                }
            }
        }
    }
}

/// Allocate across the complete room collection, never independently per card.
/// Extra artwork decorates covers and replay previews; it never creates live members or seats.
enum NanaRoomPortraitAllocator {
    private static let coverPhotoKeys = [
        "nana.pic.Dc6OjcqAodc", "nana.pic.DdJ2uSSDENz",
        "nana.pic.DczCXb6HMNj", "nana.pic.DdTY1ZoDJ_o",
        "nana.pic.DdMJA6mE7N0", "nana.pic.DdQxT9NCkQ1",
        "nana.pic.DdTmQsaCOiK", "nana.pic.DdV5vxnEs3N",
        "nana.pic.Dc6Dfy6jSal", "nana.pic.Dc_JVYmiG2t",
        "nana.pic.DctNjXIAIkT", "nana.pic.Dctezv0jcrn",
        "nana.pic.DctrZb7jKiH", "nana.pic.DcyZpWQDN_L",
        "nana.pic.Dcz55LfiUxQ", "nana.pic.DdBySv9iC1b",
        "nana.pic.DdE6ef7ETo4", "nana.pic.DdEfRgwCOY1",
        "nana.pic.DdGhSoTD1Cr", "nana.pic.DdLxPwjDqzz",
        "nana.pic.DdMv-SrHWQm", "nana.pic.DdO8NGAjTkn",
        "nana.pic.DdOkklBgBAh", "nana.pic.DdRpik8DVsi",
        "nana.pic.DdTNJvtjogw", "nana.pic.DdTelR9Apxp",
        "nana.pic.DdUCdcjCBlJ", "nana.pic.DdUMVs2jkhZ",
        "nana.pic.DdWhEvOADv0", "nana.pic.DdWps4Cl9L5",
        "nana.pic.DdYl3lqgOFb", "nana.pic.DdZjKW2CG9S",
        "nana.pic.DdaK8LKDT4g", "nana.pic.DdefHeEDp0o"
    ].filter { NanaAssetLibrary.image(for: $0) != nil }

    private static func photoLimit(for room: NanaLiveRoom) -> Int {
        switch room.seatCapacity {
        case ...3: return 4
        case 4...6: return 6
        default: return 9
        }
    }

    static func photosByRoom(
        rooms: [NanaLiveRoom], profiles: [NanaProfile], seats: [NanaRoomSeat],
        blockedProfileIDs: Set<String>, excludedPhotoKeys: Set<String> = []
    ) -> [String: [String]] {
        let orderedRooms = rooms.sorted { $0.id < $1.id }
        let profileByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let seatsByRoom = Dictionary(grouping: seats, by: \.roomID)
        // Reserve every member image before assigning decorative artwork, including
        // alternate host artwork and blocked profiles, so it cannot leak into a cover.
        let hiddenPhotos = Set(profiles.filter { blockedProfileIDs.contains($0.id) }.compactMap(\.avatarAssetKey))
            .union(rooms.filter { blockedProfileIDs.contains($0.hostID) }.compactMap(\.hostAvatarAssetKey))
            .union(excludedPhotoKeys)
        var usedProfiles: Set<String> = []
        var usedPhotos: Set<String> = []
        var result: [String: [String]] = [:]

        func assignMember(_ id: String, asset: String?, to room: NanaLiveRoom) {
            guard usedProfiles.insert(id).inserted else { return }
            guard result[room.id, default: []].count < photoLimit(for: room),
                  let asset, !usedPhotos.contains(asset), NanaAssetLibrary.image(for: asset) != nil else { return }
            usedPhotos.insert(asset)
            result[room.id, default: []].append(asset)
        }

        // A host belongs to their own room even if another room has a stale seat.
        for room in orderedRooms {
            assignMember(room.hostID, asset: room.hostAvatarAssetKey ?? profileByID[room.hostID]?.avatarAssetKey, to: room)
        }
        for room in orderedRooms {
            let members = (seatsByRoom[room.id] ?? []).sorted {
                $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position
            }
            for seat in members {
                guard let id = seat.profileID else { continue }
                assignMember(id, asset: profileByID[id]?.avatarAssetKey, to: room)
            }
        }

        // Fill in rounds so rooms share a limited photo library fairly. Never cycle
        // back to reused photos when the library runs out; leave the rest open.
        // Allocate before hiding members so every other portrait keeps its room.
        let memberPhotos = Set(profiles.compactMap(\.avatarAssetKey) + rooms.compactMap(\.hostAvatarAssetKey))
        var availablePhotos = coverPhotoKeys.filter { !memberPhotos.contains($0) && !usedPhotos.contains($0) }.makeIterator()
        for round in 0..<9 {
            for room in orderedRooms where photoLimit(for: room) > round {
                guard result[room.id, default: []].count <= round,
                      let photo = availablePhotos.next() else { continue }
                guard usedPhotos.insert(photo).inserted else { continue }
                result[room.id, default: []].append(photo)
            }
        }
        return result.mapValues { $0.filter { !hiddenPhotos.contains($0) } }
    }
}

private struct NanaVoiceRoomCard: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    let room: NanaLiveRoom
    let coverPhotos: [String]

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
                Label("\(contentStore.displayedViewerCount(for: room))", systemImage: "person.fill")
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
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_072", contentMode: .fit)
                                    .frame(width: min(tileWidth, tileHeight) * 0.4, height: min(tileWidth, tileHeight) * 0.4)
                                    .opacity(0.35)
                                    .frame(width: tileWidth, height: tileHeight)
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
    @State private var popularityTarget = "1548"
    @State private var roomTopic = ""
    @State private var seatCapacity = 3
    @State private var selectedCategory = "Open talk"
    @State private var isPublic = true
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, popularity, topic }
    private let fieldColor = Color(red: 0.065, green: 0.035, blue: 0.20)
    private let labels = ["Open talk", "Music", "Creative", "Late night"]

    var body: some View {
        ZStack {
            NanaTabBackdrop()
            VStack(spacing: 12) {
                header
                ScrollView(showsIndicators: false) {
                    creationForm
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(NanaPalette.warmWhite)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) { keyboardBar }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                focusedField = nil
                dismiss()
            } label: {
                Image(systemName: "chevron.left.circle")
                    .font(.system(size: 21, weight: .light))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back to voice rooms")
            Spacer()
            Text("Voice room").font(.system(size: 16, weight: .medium))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.top, 4)
    }

    private var creationForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            nameField
            popularityField
            introductionField
            publicSetting
            microphonePicker
            labelPicker
            if let validationMessage {
                Text(validationMessage).font(.system(size: 12))
                    .foregroundStyle(NanaPalette.softPink)
            }
            createButton
        }
    }

    private var nameField: some View {
        TextField("Please enter the room theme", text: Binding(
            get: { roomName }, set: { roomName = String($0.prefix(60)); validationMessage = nil }
        ))
        .focused($focusedField, equals: .name)
        .submitLabel(.next).onSubmit { focusedField = .popularity }
        .padding(.horizontal, 14).frame(height: 52)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("Room theme")
    }

    private var popularityField: some View {
        HStack(spacing: 12) {
            Text("Target popularity").foregroundStyle(NanaPalette.mutedWhite)
            Spacer(minLength: 0)
            TextField("1548", text: Binding(
                get: { popularityTarget },
                set: { popularityTarget = String($0.filter { $0.isASCII && $0.isNumber }.prefix(7)); validationMessage = nil }
            ))
            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            .focused($focusedField, equals: .popularity)
            .frame(width: 90).accessibilityLabel("Target popularity")
        }
        .padding(.horizontal, 14).frame(height: 52)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var introductionField: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if roomTopic.isEmpty {
                    Text("Please enter the room information")
                        .foregroundStyle(NanaPalette.mutedWhite)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { roomTopic }, set: { roomTopic = String($0.prefix(80)) }
                ))
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .topic)
                .frame(minHeight: 104)
                .accessibilityLabel("Room information, up to 80 characters")
            }
            Text("\(roomTopic.count)/80").font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(NanaPalette.mutedWhite)
        }
        .padding(12)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var publicSetting: some View {
        HStack(spacing: 12) {
            Text("Make this room public").foregroundStyle(NanaPalette.mutedWhite)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                publicOption("YES", value: true)
                publicOption("NO", value: false)
            }
            .background { Capsule().fill(.white).frame(height: 34) }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .frame(minHeight: 52)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private func publicOption(_ title: String, value: Bool) -> some View {
        Button { isPublic = value } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .foregroundStyle(isPublic == value ? .white : Color.black.opacity(0.45))
                .frame(width: 43, height: 34)
                .background(isPublic == value ? NanaPalette.violet : .clear, in: Capsule())
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value ? "Public room" : "Private room")
        .accessibilityAddTraits(isPublic == value ? [.isSelected] : [])
    }

    private var microphonePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Number of microphone seats").foregroundStyle(NanaPalette.mutedWhite)
            HStack(spacing: 8) {
                ForEach([3, 6, 9, 12], id: \.self) { capacity in
                    Button { seatCapacity = capacity } label: {
                        Text("\(capacity)").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(seatCapacity == capacity ? .white : NanaPalette.mutedWhite)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(seatCapacity == capacity ? NanaPalette.violet : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(capacity) microphone seats")
                    .accessibilityAddTraits(seatCapacity == capacity ? [.isSelected] : [])
                }
            }
        }
        .padding(14)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var labelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select label")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(labels, id: \.self) { label in
                    Button { selectedCategory = label } label: {
                        Text("# \(label)").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedCategory == label ? NanaPalette.electricLilac : NanaPalette.mutedWhite)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selectedCategory == label ? NanaPalette.violet.opacity(0.12) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(selectedCategory == label ? NanaPalette.violet : .white.opacity(0.22), lineWidth: 1))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedCategory == label ? [.isSelected] : [])
                }
            }
        }
    }

    private var createButton: some View {
        Button {
            guard !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                validationMessage = "Please enter a room theme."
                focusedField = .name
                return
            }
            guard let target = Int(popularityTarget), target > 0 else {
                validationMessage = "Enter a popularity target greater than zero."
                focusedField = .popularity
                return
            }
            validationMessage = nil
            focusedField = nil
            contentStore.explainUnavailable("Creating rooms")
        } label: {
            Text("Create a room").font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(NanaPalette.violet, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28).padding(.top, 22)
    }

    @ViewBuilder private var keyboardBar: some View {
        if focusedField != nil {
            HStack {
                Spacer()
                Button("Done") { focusedField = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 64, minHeight: 44)
            }
            .padding(.horizontal, 16).background(fieldColor)
        }
    }
}
