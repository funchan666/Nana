import SwiftUI

struct HarborGatheringView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingCreateRoom = false
    @State private var showingSearch = false
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
                                        NanaVoiceRoomCard(room: room, profiles: contentStore.payload.profiles)
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
            .sheet(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
        }
    }

    private var voiceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Voice Rooms")
                .font(.system(size: 19, weight: .bold, design: .serif).italic())
                .foregroundStyle(NanaPalette.warmWhite)
            Spacer()
            Button { showingCreateRoom = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Create").font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(NanaPalette.violet, in: Capsule())
            }
            .buttonStyle(.plain)
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
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedCategory == category ? .white : NanaPalette.mutedWhite)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(selectedCategory == category ? NanaPalette.violet : NanaPalette.card, in: Capsule())
                            .overlay(Capsule().stroke(selectedCategory == category ? NanaPalette.violet : NanaPalette.border, lineWidth: 1))
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

    private var roomBackdropKey: String {
        switch abs(room.id.hashValue) % 3 {
        case 0: return "nana.voice.room_backdrop_01"
        case 1: return "nana.voice.room_backdrop_02"
        default: return "nana.voice.room_backdrop_03"
        }
    }

    private var people: [(String, String?)] {
        let roomHost = (room.hostName, room.hostAvatarAssetKey)
        let otherPeople = profiles.filter { $0.id != room.hostID }.prefix(5).map { ($0.displayName, $0.avatarAssetKey) }
        return Array(([roomHost] + otherPeople).prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                NanaAssetImage(assetKey: roomBackdropKey)
                    .frame(maxWidth: .infinity)
                    .frame(height: 151)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.74)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 4) {
                    Text("HOT")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(NanaPalette.neonPink, in: Capsule())
                .padding(8)
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(room.viewerCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(.black.opacity(0.38), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(8)
                VStack {
                    Spacer()
                    HStack(spacing: -8) {
                        ForEach(Array(people.enumerated()), id: \.offset) { person in
                            NanaAvatarView(title: person.element.0, assetKey: person.element.1, size: 31)
                        }
                    }
                    .padding(.bottom, 13)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text(room.category)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(NanaPalette.softPink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NanaPalette.electricLilac)
                }
                Text(room.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NanaPalette.warmWhite)
                    .lineLimit(1)
                Text(room.subtitle)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(NanaPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
