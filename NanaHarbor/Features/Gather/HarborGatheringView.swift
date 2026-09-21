import SwiftUI

struct HarborGatheringView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingCreateRoom = false
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedCategory = "All rooms"

    private var rooms: [NanaLiveRoom] {
        if selectedCategory == "All rooms" { return contentStore.payload.rooms }
        return contentStore.payload.rooms.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop(imageName: "NanaLiveBackdrop")
                if contentStore.payload.rooms.isEmpty && contentStore.state(for: .rooms) == .loading {
                    NanaScreenLoading(label: "Opening rooms")
                } else if contentStore.payload.rooms.isEmpty, case .failed(let error) = contentStore.state(for: .rooms) {
                    NanaErrorState(title: "Rooms are unavailable", detail: error.localizedDescription, actionTitle: "Retry") { Task { await contentStore.refresh(.rooms) } }
                } else { ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        roomFilters
                        if rooms.isEmpty {
                            NanaEmptyState(title: "No rooms in this category", detail: "Create a room and give the next conversation a place to land.", actionTitle: "Create a room") { showingCreateRoom = true }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(rooms) { room in
                                    Button { selectedRoom = room } label: { roomCard(room) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                } }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await contentStore.refresh(.rooms) }
            .sheet(isPresented: $showingCreateRoom) { NanaCreateRoomView() }
            .sheet(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("VOICE ROOMS")
                    .font(NanaType.stamp)
                    .tracking(1.4)
                    .foregroundStyle(NanaPalette.softPink)
                Text("Stay for the voice.")
                    .font(NanaType.hero)
                    .foregroundStyle(NanaPalette.warmWhite)
                Text("A few rooms are already open.")
                    .font(NanaType.body)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            Button { showingCreateRoom = true } label: {
                Label("Create", systemImage: "plus")
                    .font(NanaType.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(NanaPalette.violet, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var roomFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NanaChip(title: "All rooms", isSelected: selectedCategory == "All rooms") { selectedCategory = "All rooms" }
                ForEach(["Late night", "Creative", "Music", "Open talk"], id: \.self) { category in
                    NanaChip(title: category, isSelected: selectedCategory == category) { selectedCategory = category }
                }
            }
        }
    }

    private func roomCard(_ room: NanaLiveRoom) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NanaRoomArtwork(room: room, height: 178)
            HStack(spacing: 11) {
                NanaPlaceholderPortrait(title: room.hostName, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.hostName)
                        .font(NanaType.bodyMedium)
                        .foregroundStyle(NanaPalette.warmWhite)
                    Text("\(room.seatCapacity) seats · \(room.viewerCount) listening")
                        .font(NanaType.caption)
                        .foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NanaPalette.electricLilac)
            }
            .padding(13)
        }
        .nanaCard()
    }
}

private struct NanaCreateRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var roomName = ""
    @State private var roomTopic = ""
    @State private var seatCapacity = 6
    @State private var selectedCategory = "Open talk"

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Create a room")
                            .font(NanaType.hero)
                            .foregroundStyle(NanaPalette.warmWhite)
                        Text("Give the next conversation a clear shape.")
                            .font(NanaType.body)
                            .foregroundStyle(NanaPalette.mutedWhite)
                        TextField("Room title", text: $roomName)
                            .foregroundStyle(.white)
                            .nanaGlassField()
                        TextField("What is this room about?", text: $roomTopic)
                            .foregroundStyle(.white)
                            .nanaGlassField()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Seats")
                                .font(NanaType.caption.weight(.semibold))
                                .foregroundStyle(NanaPalette.mutedWhite)
                            Picker("Seats", selection: $seatCapacity) {
                                ForEach([3, 6, 9, 12], id: \.self) { Text("\($0) microphones").tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Category")
                                .font(NanaType.caption.weight(.semibold))
                                .foregroundStyle(NanaPalette.mutedWhite)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(["Open talk", "Creative", "Music", "Late night"], id: \.self) { category in NanaChip(title: category, isSelected: selectedCategory == category) { selectedCategory = category } } }
                            }
                        }
                        Button {
                            guard !roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            contentStore.explainUnavailable("Creating rooms")
                        } label: { Text("Create a room").frame(maxWidth: .infinity) }
                        .buttonStyle(NanaPrimaryButtonStyle())
                        .padding(.top, 8)
                    }
                    .padding(22)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) }
            }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}
