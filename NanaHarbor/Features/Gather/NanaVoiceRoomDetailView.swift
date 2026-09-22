import SwiftUI

struct NanaVoiceRoomDetailView: View {
    let room: NanaLiveRoom

    var body: some View {
        NanaLiveRoomView(room: room, presentation: .voice)
    }
}

/// Seats sit directly on the supplied stage artwork, with no nested preview or cards.
struct NanaVoiceStageView: View {
    let room: NanaLiveRoom
    let requestMicrophone: () -> Void
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedProfile: NanaProfile?

    private var capacity: Int { min(12, max(1, room.seatCapacity)) }
    private var rowCount: Int { capacity == 3 ? 2 : capacity == 9 ? 3 : (capacity + columnCount - 1) / columnCount }
    private var columnCount: Int { capacity > 6 ? 4 : 3 }
    private var loadedSeats: [NanaRoomSeat] {
        contentStore.payload.roomSeats.filter { $0.roomID == room.id }
    }

    private func seat(at index: Int) -> NanaRoomSeat {
        if let seat = loadedSeats.first(where: { $0.position == index }) { return seat }
        // The host fallback only applies before a room has supplied its seat roster.
        let isHost = index == 0 && loadedSeats.isEmpty
        return NanaRoomSeat(
            id: "\(room.id)-seat-\(index)", roomID: room.id, position: index,
            profileID: isHost ? room.hostID : nil,
            displayName: isHost ? room.hostName : nil,
            role: isHost ? "Host" : "Listener", isMuted: false, isInvited: false
        )
    }

    private func position(for index: Int, in size: CGSize) -> CGPoint {
        let column: CGFloat
        let row: Int
        if capacity == 3 {
            column = index == 0 ? 0.5 : (index == 1 ? 0.23 : 0.77)
            row = index == 0 ? 0 : 1
        } else if capacity == 9 {
            column = index == 0 ? 0.5 : (CGFloat((index - 1) % 4) + 0.5) / 4
            row = index == 0 ? 0 : 1 + (index - 1) / 4
        } else {
            column = (CGFloat(index % columnCount) + 0.5) / CGFloat(columnCount)
            row = index / columnCount
        }
        return CGPoint(x: size.width * column, y: size.height * (CGFloat(row) + 0.5) / CGFloat(rowCount))
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(columnCount == 4 ? 48.0 : 56.0, max(30, geometry.size.height / CGFloat(rowCount) - 46))
            ZStack {
                ForEach(0..<capacity, id: \.self) { index in
                    seatButton(seat(at: index), diameter: capacity == 3 && index == 0 ? diameter * 1.3 : diameter)
                        .frame(width: geometry.size.width / CGFloat(columnCount))
                        .position(position(for: index, in: geometry.size))
                }
            }
        }
        .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
    }

    private func seatButton(_ seat: NanaRoomSeat, diameter: CGFloat) -> some View {
        let profile = seat.profileID.flatMap { contentStore.profile(with: $0) }
        let isHost = seat.profileID == room.hostID
        let occupied = seat.profileID != nil
        let name = profile?.displayName ?? seat.displayName ?? (isHost ? room.hostName : "Guest")
        let portrait = profile?.avatarAssetKey ?? (isHost ? room.hostAvatarAssetKey : nil)

        return Button {
            if let profile { selectedProfile = profile }
            else if occupied { contentStore.explainUnavailable("This member's profile") }
            else { requestMicrophone() }
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    if occupied {
                        NanaAvatarView(title: name, assetKey: portrait, size: diameter)
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_\(seat.isMuted ? "071" : "134")", contentMode: .fit)
                            .frame(width: 15, height: 15)
                    } else {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_072", contentMode: .fit)
                            .frame(width: diameter, height: diameter).opacity(0.8)
                    }
                }
                .overlay(alignment: .top) {
                    if isHost {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_070", contentMode: .fit)
                            .frame(width: 56, height: 15).offset(y: -17)
                    }
                }
                Text(occupied ? name.components(separatedBy: " ").first ?? name : String(seat.position + 1))
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                if !occupied {
                    Text("open").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(minHeight: 44).frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(occupied ? "\(name), \(isHost ? "host" : "speaker")\(seat.isMuted ? ", muted" : "")" : "Join microphone \(seat.position + 1)")
    }
}
