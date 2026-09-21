import SwiftUI

struct NanaVoiceRoomDetailView: View {
    let room: NanaLiveRoom
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var isLocalMuted = false
    @State private var showingGiftShelf = false
    @State private var showingExitConfirmation = false
    @State private var messageDraft = ""
    @State private var selectedProfile: NanaProfile?

    private var roomSeats: [NanaRoomSeat] {
        let loadedSeats = contentStore.payload.roomSeats.filter { $0.roomID == room.id }.sorted { $0.position < $1.position }
        guard !loadedSeats.isEmpty else {
            return (0..<room.seatCapacity).map { position in
                NanaRoomSeat(
                    id: "\(room.id)-stage-\(position)",
                    roomID: room.id,
                    position: position,
                    profileID: position == 0 ? room.hostID : nil,
                    displayName: position == 0 ? room.hostName : nil,
                    role: position == 0 ? "Host" : "Open seat",
                    isMuted: false,
                    isInvited: false
                )
            }
        }
        return loadedSeats
    }

    private var roomMessages: [NanaRoomChatMessage] {
        contentStore.payload.roomMessages.filter { $0.roomID == room.id }
    }

    var body: some View {
        ZStack {
            NanaBackdrop(imageName: "nana.voice.room_backdrop_01")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    topBar
                    streamPreview
                    roomHeader
                    seatGrid
                    liveChat
                    actionRail
                    composer
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if room.id == "room-aurora" { await contentStore.refresh(.auroraRoom) }
        }
        .confirmationDialog("Leave this room?", isPresented: $showingExitConfirmation, titleVisibility: .visible) {
            Button("Leave room", role: .destructive) { dismiss() }
            Button("Stay", role: .cancel) { }
        }
        .sheet(isPresented: $showingGiftShelf) { NanaGiftShelfView(roomID: room.id) }
        .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
        .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button { showingExitConfirmation = true } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.22), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(NanaPalette.neonPink).frame(width: 7, height: 7)
                Text("LIVE")
                    .font(NanaType.stamp)
                    .tracking(1.3)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.24), in: Capsule())
            Spacer()
            Button { } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.22), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var streamPreview: some View {
        ZStack(alignment: .bottomLeading) {
            NanaAssetImage(assetKey: "nana.voice.room_backdrop_01")
                .frame(maxWidth: .infinity)
                .frame(height: 278)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                HStack {
                    HStack(spacing: 7) {
                        NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.hostName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Lv.\(max(room.seatCapacity, 1) + 22) · \(room.viewerCount) listening")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    Spacer()
                    Text("\(room.viewerCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.black.opacity(0.3), in: Capsule())
                }
                .padding(.horizontal, 12)
                Spacer()
                HStack(spacing: -10) {
                    ForEach(roomSeats.prefix(6)) { seat in
                        NanaAvatarView(title: seat.displayName ?? "Open seat", assetKey: seat.profileID == room.hostID ? room.hostAvatarAssetKey : nil, size: 39)
                    }
                }
                Text(room.title)
                    .font(.system(size: 18, weight: .bold, design: .serif).italic())
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(NanaPalette.neonPink, in: Capsule())
                    Text(room.category)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(.bottom, 12)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("VOICE ROOM")
                    .font(NanaType.stamp)
                    .tracking(1.2)
                    .foregroundStyle(NanaPalette.softPink)
                Text("The stage is ready for the next voice.")
                    .font(NanaType.caption)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1))
    }

    private var roomHeader: some View {
        HStack(alignment: .top, spacing: 11) {
            NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(room.title)
                    .font(NanaType.section)
                    .foregroundStyle(NanaPalette.warmWhite)
                Text("Hosted by \(room.hostName) · \(room.viewerCount) listening")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
                Text(room.subtitle)
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(2)
            }
            Spacer()
            Button { contentStore.toggleConnection(for: room.hostID) } label: {
                Text(room.isFollowingHost ? "Following" : "Follow")
                    .font(NanaType.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(room.isFollowingHost ? NanaPalette.cardStrong : NanaPalette.violet, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var seatGrid: some View {
        VStack(alignment: .leading, spacing: 11) {
            NanaSectionTitle(eyebrow: "The stage", title: "\(room.seatCapacity) microphones")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
                ForEach(roomSeats) { seat in
                    Button {
                        if let profileID = seat.profileID, let profile = contentStore.profile(with: profileID) { selectedProfile = profile }
                    } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottomTrailing) {
                                NanaPlaceholderPortrait(title: seat.displayName ?? "Open seat", size: 54)
                                if seat.isMuted {
                                    Image(systemName: "mic.slash.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(5)
                                        .background(NanaPalette.warning, in: Circle())
                                }
                            }
                            Text(seat.displayName ?? "Open seat")
                                .font(NanaType.caption.weight(.semibold))
                                .foregroundStyle(seat.profileID == nil ? NanaPalette.mutedWhite : NanaPalette.warmWhite)
                                .lineLimit(1)
                            Text(seat.role)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(NanaPalette.mutedWhite)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(seat.profileID == nil ? NanaPalette.card.opacity(0.5) : NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(seat.profileID == nil ? NanaPalette.border : NanaPalette.violet.opacity(0.65), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if seat.profileID != nil {
                            Button(seat.isMuted ? "Unmute" : "Mute") { contentStore.toggleMute(roomID: room.id, seatID: seat.id) }
                            Button("Remove from room", role: .destructive) { contentStore.kick(roomID: room.id, seatID: seat.id) }
                        }
                    }
                }
            }
        }
    }

    private var liveChat: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Room chat")
                    .font(NanaType.bodyMedium)
                    .foregroundStyle(NanaPalette.warmWhite)
                Spacer()
                Text("\(roomMessages.count) messages")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(roomMessages.suffix(4)) { message in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(message.senderName)
                            .font(NanaType.caption.weight(.bold))
                            .foregroundStyle(NanaPalette.electricLilac)
                        Text(message.body)
                            .font(NanaType.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .nanaCard()
        }
    }

    private var actionRail: some View {
        HStack(spacing: 8) {
            NanaRoundAction(icon: isLocalMuted ? "mic.slash" : "mic", title: isLocalMuted ? "Muted" : "Mic", tint: isLocalMuted ? NanaPalette.warning : NanaPalette.violet) { isLocalMuted.toggle() }
            NanaRoundAction(icon: "music.note", title: "Music", tint: NanaPalette.deepSpace) { contentStore.explainUnavailable("Room music") }
            NanaRoundAction(icon: "gift", title: "Gift", tint: NanaPalette.neonPink) { showingGiftShelf = true }
            NanaRoundAction(icon: "person.badge.plus", title: "Invite", tint: NanaPalette.deepSpace) { contentStore.explainUnavailable("Room invitations") }
        }
        .padding(12)
        .nanaCard()
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Say something…", text: $messageDraft)
                .foregroundStyle(.white)
                .font(NanaType.body)
                .nanaGlassField()
            Button {
                contentStore.appendRoomMessage(roomID: room.id, body: messageDraft)
                messageDraft = ""
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(NanaPalette.violet, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct NanaGiftShelfView: View {
    let roomID: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Send a gift")
                                .font(NanaType.hero)
                                .foregroundStyle(NanaPalette.warmWhite)
                            Text("Balance \(contentStore.payload.wallet.coinBalance) coins")
                                .font(NanaType.caption)
                                .foregroundStyle(NanaPalette.mutedWhite)
                        }
                        Spacer()
                        Image("NanaGiftArtwork")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 76, height: 50)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(contentStore.payload.gifts) { gift in
                            Button {
                                contentStore.sendGift(gift, to: roomID)
                            } label: {
                                VStack(spacing: 9) {
                                    NanaAssetImage(assetKey: gift.assetKey ?? "nana.asset.NanaGiftArtwork", contentMode: .fit)
                                        .frame(width: 78, height: 58)
                                    Text(gift.title)
                                        .font(NanaType.bodyMedium)
                                        .foregroundStyle(NanaPalette.warmWhite)
                                    Text("\(gift.coinCost) coins")
                                        .font(NanaType.caption)
                                        .foregroundStyle(NanaPalette.softPink)
                                }
                                .frame(maxWidth: .infinity, minHeight: 130)
                                .nanaCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .task { await contentStore.refresh(.gifts) }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}
