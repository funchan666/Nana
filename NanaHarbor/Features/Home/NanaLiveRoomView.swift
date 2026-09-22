import SwiftUI
import AVFoundation
import UIKit

/// The room owns one player. Feed cards remain static first-frame covers.
struct NanaLiveRoomView: View {
    enum Presentation { case video, voice }
    private let presentation: Presentation
    @State private var room: NanaLiveRoom
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var panel: RoomPanel?
    @State private var messageDraft = ""
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var selectedGiftID: String?
    @State private var giftQuantity = 1
    @State private var showingWallet = false
    @State private var showingGiftConfirmation = false
    @State private var showingInsufficientCoins = false
    @State private var conversation: NanaConversation?
    @FocusState private var composerFocused: Bool

    init(room: NanaLiveRoom, presentation: Presentation = .video) {
        _room = State(initialValue: room)
        self.presentation = presentation
    }

    private enum RoomPanel: String {
        case host = "Anchor Information", audience = "Room audience"
        case ranking = "Live room ranking", heat = "Room heat ranking"
        case more = "More rooms", quick = "Quick messages", connection = "Voice chat"
        case gifts = "Gift Giving", exit = "Exit room confirmation", options = "Room settings"
        case music = "Music on demand"
    }

    private var host: NanaProfile? { contentStore.profile(with: room.hostID) }
    private var isFollowing: Bool { contentStore.personal.following[room.hostID] ?? room.isFollowingHost }
    private var messages: [NanaRoomChatMessage] { contentStore.payload.roomMessages.filter { $0.roomID == room.id } }
    private var participants: [NanaProfile] {
        let ids = Set(contentStore.payload.roomSeats.filter { $0.roomID == room.id }.compactMap(\.profileID))
        return contentStore.payload.profiles.filter { ids.contains($0.id) && !contentStore.blockedProfileIDs.contains($0.id) }
    }
    private var gifts: [NanaGift] { contentStore.payload.gifts.filter { $0.coinCost >= 0 } }
    private var selectedGift: NanaGift? { gifts.first { $0.id == selectedGiftID } ?? gifts.first }
    private var giftTotal: Int {
        guard let gift = selectedGift else { return 0 }
        let result = gift.coinCost.multipliedReportingOverflow(by: giftQuantity)
        return result.overflow ? Int.max : result.partialValue
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                roomBackground
                VStack(spacing: 8) {
                    roomTopBar
                    roomStatusBar
                    if presentation == .voice && !composerFocused {
                        voiceThemeBar
                        NanaVoiceStageView(room: room) { open(.connection) }
                            .frame(height: min(360, geometry.size.height * 0.43))
                    }
                    Spacer(minLength: 0)
                    chatOverlay(maxHeight: geometry.size.height * (presentation == .voice ? 0.20 : 0.30))
                    roomComposer
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
                if let panel {
                    Color.black.opacity(0.46).ignoresSafeArea()
                        .onTapGesture { self.panel = nil }
                    if panel == .more || panel == .music {
                        roomPanel(panel, availableHeight: geometry.size.height)
                            .frame(width: geometry.size.width * 0.8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        roomPanel(panel, availableHeight: geometry.size.height)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: panel)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task(id: room.id) {
            startPlayback()
            messageDraft = contentStore.draft(for: "live-room-\(room.id)")
            if room.id == "room-aurora" { await contentStore.refresh(.auroraRoom) }
        }
        .onDisappear {
            _ = contentStore.saveDraft(messageDraft, for: "live-room-\(room.id)")
            stopPlayback()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isPlaying { player?.play() } else { player?.pause() }
        }
        .sheet(isPresented: $showingWallet) { NanaWalletView() }
        .sheet(item: $conversation) { NanaConversationView(conversation: $0) }
        .alert("Send this gift?", isPresented: $showingGiftConfirmation) {
            Button("Send") { sendGift() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(selectedGift?.title ?? "Gift") × \(giftQuantity) costs \(giftTotal) coins.")
        }
        .alert("More coins needed", isPresented: $showingInsufficientCoins) {
            Button("Open Wallet") { showingWallet = true }
            Button("Cancel", role: .cancel) { }
        } message: { Text("You need \(giftTotal) coins. Your balance is \(coinStore.balance).") }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private var roomBackground: some View {
        ZStack {
            Color.black
            if presentation == .voice {
                GeometryReader { geometry in
                    NanaAssetImage(assetKey: "nana.voice.room_backdrop_01")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            } else if let player {
                NanaLiveVideoSurface(player: player)
            } else if let asset = room.streamAssetKey {
                NanaMediaPreview(assetKey: asset)
            } else {
                NanaAssetImage(assetKey: room.hostAvatarAssetKey ?? "nana.photo.photo_asset_014")
            }
            LinearGradient(colors: [.black.opacity(presentation == .voice ? 0.18 : 0.42), .clear, .black.opacity(presentation == .voice ? 0.08 : 0.16), .black.opacity(presentation == .voice ? 0.3 : 0.8)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var roomTopBar: some View {
        HStack(spacing: 4) {
            Button { open(.host) } label: {
                HStack(spacing: 6) {
                    NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.hostName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(host.map { "\($0.age) · \($0.region) · Lv.\($0.level)" } ?? room.category)
                            .font(.system(size: 8)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6).padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View host information")
            Spacer(minLength: 0)
            Button { open(.audience) } label: {
                HStack(spacing: 3) {
                    HStack(spacing: -7) {
                        ForEach(participants.prefix(3)) { profile in
                            NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 19)
                        }
                    }
                    Text(room.viewerCount.formatted()).font(.system(size: 10))
                }
                .frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("Room audience, \(room.viewerCount)")
            symbolButton("ellipsis.circle", title: "Room options") { open(.options) }
            symbolButton("xmark.circle", title: "Leave room") { open(.exit) }
        }
    }

    private var roomStatusBar: some View {
        HStack(spacing: 7) {
            artworkButton("055", title: "Room ranking", size: 30) { open(.ranking) }
            Button { open(.heat) } label: {
                HStack(spacing: 3) {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_009", contentMode: .fit).frame(width: 14, height: 17)
                    Text("Room heat").font(.system(size: 9))
                    Image(systemName: "chevron.right").font(.system(size: 8))
                }.padding(6).background(.black.opacity(0.3), in: Capsule())
            }.buttonStyle(.plain).frame(minHeight: 44)
            Spacer()
            Text(presentation == .voice ? "Voice room" : room.streamSourceType == "simulatedReplay" ? "Video replay" : room.roomState)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.black.opacity(0.3), in: Capsule())
            symbolButton("chevron.left", title: "More rooms") { open(.more) }
        }
    }

    private var voiceThemeBar: some View {
        HStack(spacing: 8) {
            Text(room.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(room.subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            Spacer(minLength: 0)
            Button { open(.music) } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_077", contentMode: .fit)
                    .frame(width: 22, height: 22).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Music on demand")
        }
    }

    private var musicPanel: some View {
        VStack(spacing: 18) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_065", contentMode: .fit)
                .frame(width: 72, height: 72).padding(.top, 28)
            Text("No tracks available yet").font(.system(size: 15, weight: .semibold))
            panelNote("The room music library is not available yet. Tracks will appear here when the service provides them.")
        }
    }

    private func chatOverlay(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if presentation == .video && player == nil {
                Text("Video is currently unavailable.")
                    .font(.system(size: 11)).padding(10)
                    .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 9))
            }
            Text("Keep this room respectful. No harassment, hateful content or harmful material.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                .padding(9).frame(maxWidth: 270, alignment: .leading)
                .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 9))
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(messages) { message in
                            (Text("\(message.senderName):  ").foregroundColor(NanaPalette.neonPink) + Text(message.body).foregroundColor(.white))
                                .font(.system(size: 11))
                                .padding(9)
                                .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 9))
                                .id(message.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: messages.isEmpty ? 0 : maxHeight)
                .onChange(of: messages.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roomComposer: some View {
        HStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "text.bubble").font(.system(size: 12))
                TextField("Say something", text: $messageDraft)
                    .font(.system(size: 12)).focused($composerFocused)
                    .submitLabel(.send).onSubmit { submitMessage(messageDraft) }
                Button {
                    if messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { open(.quick) }
                    else { submitMessage(messageDraft) }
                } label: {
                    Image(systemName: messageDraft.isEmpty ? "ellipsis" : "paperplane.fill")
                        .font(.system(size: 13)).frame(width: 32, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(messageDraft.isEmpty ? "Quick messages" : "Send message")
            }
            .padding(.leading, 10)
            .background(.black.opacity(0.4), in: Capsule())
            artworkButton(presentation == .voice ? "074" : "093", title: "Voice chat") { open(.connection) }
            ShareLink(item: "Join \(room.hostName) in \(room.title) on Nana.") {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_094", contentMode: .fit).frame(width: 34, height: 34).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Share room")
            artworkButton("086", title: "Send a gift") { open(.gifts) }
            artworkButton("075", title: "Room heat") { open(.heat) }
        }
    }

    private func roomPanel(_ panel: RoomPanel, availableHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(panel.rawValue).font(.system(size: 18, weight: .heavy).italic())
                Spacer()
                symbolButton("xmark.circle", title: "Close panel") { self.panel = nil }
            }
            ScrollView(showsIndicators: false) { panelContent(panel) }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .frame(height: (panel == .more || panel == .music) ? availableHeight : min(availableHeight * 0.76, panel == .exit ? 230 : panel == .gifts ? 450 : 430))
        .background(Color(red: 0.055, green: 0.035, blue: 0.085).opacity(0.97), in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
    }

    @ViewBuilder private func panelContent(_ panel: RoomPanel) -> some View {
        switch panel {
        case .host: hostPanel
        case .audience: audiencePanel
        case .ranking, .heat: rankingPanel(isHeat: panel == .heat)
        case .quick: quickMessagesPanel
        case .connection: connectionPanel
        case .gifts: giftPanel
        case .more: moreRoomsPanel
        case .exit: exitPanel
        case .options: optionsPanel
        case .music: musicPanel
        }
    }

    private var hostPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(room.hostName).font(.system(size: 15, weight: .semibold))
                    Text(host.map { "\($0.region) · Lv.\($0.level)" } ?? room.category).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                }
            }
            Text(host?.introduction ?? room.subtitle).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            HStack(spacing: 8) {
                metric("Fans", value: host.map { String($0.followerCount) } ?? "—", color: .green)
                metric("Following", value: host.map { String($0.followingCount) } ?? "—", color: .cyan)
                metric("Audience", value: String(room.viewerCount), color: .orange)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(room.title).font(.system(size: 14, weight: .medium))
                Text(room.subtitle).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                Button {
                    if let thread = contentStore.visibleConversations.first(where: { $0.profileID == room.hostID }) { conversation = thread }
                    else { contentStore.explainUnavailable("Starting a private message") }
                } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_125", contentMode: .fit).frame(height: 38)
                }.buttonStyle(.plain).frame(minHeight: 44).accessibilityLabel("Private message")
                followButton
            }
        }
    }

    private var audiencePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(room.viewerCount) viewers").font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            if participants.isEmpty {
                panelNote("The audience list is not available yet.")
            } else {
                Text("On stage").font(.system(size: 11)).foregroundStyle(NanaPalette.electricLilac)
                ForEach(participants) { profile in
                    HStack(spacing: 10) {
                        NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName).font(.system(size: 13, weight: .medium))
                            Text("\(profile.region) · Lv.\(profile.level)").font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
                        }
                        Spacer()
                    }.padding(10).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }

    private func rankingPanel(isHeat: Bool) -> some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isHeat ? "Room popularity" : room.title).font(.system(size: 15, weight: .semibold))
                    Text("No rankings yet").font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer()
                NanaAssetImage(assetKey: "nana.voice.voice_asset_\(isHeat ? "009" : "008")", contentMode: .fit).frame(width: 76, height: 68)
            }.padding(14).background(NanaPalette.violet.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            panelNote("Rankings will appear when room activity is available from the service.")
        }
    }

    private var quickMessagesPanel: some View {
        VStack(spacing: 10) {
            ForEach(["Hello everyone!", "Great room!", "Can you say hello?", "I really like your style!", "What song is this?", "Thank you!"], id: \.self) { message in
                Button { self.panel = nil; messageDraft = message; composerFocused = true } label: {
                    HStack {
                        Text(message).font(.system(size: 12))
                        Spacer()
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_102", contentMode: .fit).frame(width: 43, height: 26)
                    }.padding(.horizontal, 12).frame(minHeight: 48).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }

    private var connectionPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer().frame(width: 83)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice connection").font(.system(size: 14, weight: .semibold))
                    Text("Not connected").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer()
            }.padding(12).frame(height: 100)
                .background {
                    GeometryReader { geometry in
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_078")
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            panelNote("Voice connections will be available when the room service supports joining the microphone.")
            Button("Request to join") { contentStore.explainUnavailable("Joining voice chat") }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
        }
    }

    private var giftPanel: some View {
        VStack(spacing: 18) {
            if gifts.isEmpty { panelNote("The gift catalog is not available yet.") }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 16) {
                ForEach(gifts) { gift in
                    Button { selectedGiftID = gift.id } label: {
                        VStack(spacing: 6) {
                            NanaAssetImage(assetKey: gift.assetKey ?? "nana.voice.voice_asset_083", contentMode: .fit)
                                .frame(height: 53).frame(maxWidth: .infinity)
                                .padding(6)
                                .background(selectedGift?.id == gift.id ? NanaPalette.violet.opacity(0.35) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedGift?.id == gift.id ? NanaPalette.violet : .clear))
                            Text(gift.coinCost == 0 ? "Free" : "\(gift.coinCost)")
                                .font(.system(size: 11)).foregroundStyle(gift.coinCost == 0 ? .green : .yellow)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(gift.title), \(gift.coinCost) coins")
                }
            }
            HStack(spacing: 4) {
                Button { showingWallet = true } label: {
                    HStack(spacing: 7) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 31, height: 31)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coinStore.balance.formatted()).font(.system(size: 13, weight: .medium))
                            Text("Balance").font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
                        }
                    }
                }.buttonStyle(.plain).accessibilityLabel("Balance \(coinStore.balance) coins. Open wallet")
                Spacer(minLength: 0)
                symbolButton("minus.circle", title: "Decrease quantity") { giftQuantity = max(1, giftQuantity - 1) }
                Text("\(giftQuantity)").font(.system(size: 13)).monospacedDigit()
                symbolButton("plus.circle", title: "Increase quantity") { giftQuantity = min(99, giftQuantity + 1) }
                artworkButton("102", title: "Send selected gift") {
                    guard selectedGift != nil else { return }
                    if coinStore.balance < giftTotal { showingInsufficientCoins = true }
                    else { showingGiftConfirmation = true }
                }.disabled(selectedGift == nil)
            }.padding(9).background(.white.opacity(0.09), in: Capsule())
            if selectedGift != nil { Text("Total: \(giftTotal) coins").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite) }
        }
    }

    private var moreRoomsPanel: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(contentStore.payload.rooms.filter { $0.id != room.id && !contentStore.blockedProfileIDs.contains($0.hostID) }) { other in
                Button {
                    _ = contentStore.saveDraft(messageDraft, for: "live-room-\(room.id)")
                    panel = nil
                    room = other
                } label: {
                    NanaRoomArtwork(room: other, height: 175)
                }.buttonStyle(.plain)
            }
        }
    }

    private var exitPanel: some View {
        VStack(spacing: 20) {
            panelNote("Leave this room? Follow the host to find them again.")
            HStack(spacing: 10) {
                Button {
                    _ = contentStore.saveDraft(messageDraft, for: "live-room-\(room.id)")
                    stopPlayback(); dismiss()
                } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_151", contentMode: .fit).frame(height: 38)
                }.buttonStyle(.plain).frame(minHeight: 44).accessibilityLabel("Exit the room")
                followButton
            }
        }
    }

    private var optionsPanel: some View {
        VStack(spacing: 10) {
            if presentation == .video {
                Button(isMuted ? "Turn sound on" : "Mute sound") { isMuted.toggle(); player?.isMuted = isMuted }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
                Button(isPlaying ? "Pause video" : "Play video") {
                    isPlaying.toggle()
                    if isPlaying { player?.play() } else { player?.pause() }
                }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
            }
            if presentation == .voice {
                Button("Music on demand") { open(.music) }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
                Button("Join a microphone") { open(.connection) }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
            }
            Button("Quick messages") { open(.quick) }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
            Button("Hide this host") { contentStore.block(profileID: room.hostID) }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.deepSpace))
        }
    }

    private var followButton: some View {
        Button {
            guard host != nil else { contentStore.explainUnavailable("Following this host"); return }
            contentStore.toggleConnection(for: room.hostID)
        } label: {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_\(isFollowing ? "101" : "100")", contentMode: .fit).frame(height: 38)
        }.buttonStyle(.plain).frame(minHeight: 44).accessibilityLabel(isFollowing ? "Unfollow host" : "Follow host")
    }

    private func panelNote(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) { Text(value).foregroundStyle(color); Text(title).foregroundStyle(NanaPalette.mutedWhite) }
            .font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 48).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
    private func symbolButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17)).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(title)
    }
    private func artworkButton(_ number: String, title: String, size: CGFloat = 34, action: @escaping () -> Void) -> some View {
        Button(action: action) { NanaAssetImage(assetKey: "nana.voice.voice_asset_\(number)", contentMode: .fit).frame(width: size, height: size).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(title)
    }
    private func open(_ panel: RoomPanel) {
        composerFocused = false
        self.panel = panel
        if panel == .gifts { Task { await contentStore.refresh(.gifts) } }
    }
    private func submitMessage(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = contentStore.saveDraft(text, for: "live-room-\(room.id)")
        contentStore.appendRoomMessage(roomID: room.id, body: text)
        composerFocused = false
    }
    private func sendGift() {
        guard let gift = selectedGift else { return }
        guard coinStore.balance >= giftTotal else { showingInsufficientCoins = true; return }
        // The current service has no gift-write contract. Never debit a local balance
        // or claim delivery while the existing send action is unavailable.
        contentStore.sendGift(gift, to: room.id)
    }
    private func startPlayback() {
        stopPlayback()
        guard presentation == .video, let asset = room.streamAssetKey, let url = NanaAssetLibrary.videoURL(for: asset) else { return }
        let queue = AVQueuePlayer()
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        queue.isMuted = isMuted
        isPlaying = true
        queue.play()
    }
    private func stopPlayback() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
    }
}

private struct NanaLiveVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> NanaLiveVideoLayerView {
        let view = NanaLiveVideoLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: NanaLiveVideoLayerView, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: NanaLiveVideoLayerView, coordinator: ()) { view.playerLayer.player = nil }
}

private final class NanaLiveVideoLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
