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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @StateObject private var voiceConnection = NanaVoiceConnectionSession()
    @StateObject private var roomMusic = NanaRoomMusicPlayer()
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var panel: RoomPanel?
    @State private var messageDraft = ""
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var selectedGiftID: String?
    @State private var giftQuantity = 1
    @State private var showingWallet = false
    @State private var pendingGiftReceipt: NanaRoomGiftReceipt?
    @State private var pendingGiftAccountID: String?
    @State private var giftConfirmationError: String?
    @State private var sentGiftReceipt: NanaRoomGiftReceipt?
    @State private var isSendingGift = false
    @State private var showingInsufficientCoins = false
    @State private var conversation: NanaConversation?
    @State private var selectedProfile: NanaProfile?
    @State private var panelContentHeights: [String: CGFloat] = [:]
    @State private var moreRoomCategory = "All"
    @State private var reportReason = "Harassment"
    @State private var showingBlockConfirmation = false
    @State private var moderationSuccess: AccountEntryNotice?
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
        case music = "Music on demand", report = "Report"
    }

    private var host: NanaProfile? { contentStore.profile(with: room.hostID) }
    private var isFollowing: Bool { contentStore.isFollowing(room.hostID) }
    private var messages: [NanaRoomChatMessage] {
        let published = contentStore.roomMessages(for: room.id)
        let sent = coinStore.roomGiftReceipts.filter { $0.roomID == room.id }.map(\.chatMessage)
        return published + sent
    }
    private var participants: [NanaProfile] {
        let ids = Set(contentStore.payload.roomSeats.filter { $0.roomID == room.id }.compactMap(\.profileID))
        return contentStore.payload.profiles.filter { ids.contains($0.id) && !contentStore.hiddenAuthorIDs.contains($0.id) }
    }
    private struct AudiencePortrait: Identifiable {
        let id: String
        let title: String
        let assetKey: String?
    }

    private var replayAudience: [NanaReplayAudienceMember] { contentStore.replayAudience(for: room) }
    private var audienceCount: Int { contentStore.displayedViewerCount(for: room) }

    private var audiencePortraits: [AudiencePortrait] {
        if room.streamSourceType == "simulatedReplay" {
            return replayAudience.prefix(4).map {
                AudiencePortrait(id: $0.id, title: $0.displayName, assetKey: $0.avatarAssetKey)
            }
        }
        var usedPhotos = Set([room.hostAvatarAssetKey, host?.avatarAssetKey].compactMap { $0 })
        let portraits = participants.filter { $0.id != room.hostID }.compactMap { profile -> AudiencePortrait? in
            if let asset = profile.avatarAssetKey, !usedPhotos.insert(asset).inserted { return nil }
            return AudiencePortrait(id: profile.id, title: profile.displayName, assetKey: profile.avatarAssetKey)
        }
        return Array(portraits.prefix(4))
    }

    private var showsReplayActivity: Bool {
        room.streamSourceType == "simulatedReplay" && (presentation == .voice || player != nil)
    }
    private var replayActivityIsActive: Bool {
        scenePhase == .active && showsReplayActivity && (presentation == .voice || isPlaying) && panel == nil
            && pendingGiftReceipt == nil && moderationSuccess == nil
            && !composerFocused && !showingWallet && conversation == nil
    }
    private var gifts: [NanaGift] { NanaGift.roomCatalog }
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
                            .frame(height: min(300, geometry.size.height * 0.34))
                    }
                    if presentation == .video && voiceConnection.isActive && !composerFocused {
                        HStack {
                            Spacer()
                            NanaVoiceConnectionTiles(
                                session: voiceConnection, hostName: room.hostName,
                                hostAvatar: room.hostAvatarAssetKey ?? host?.avatarAssetKey,
                                account: sessionStore.activeProfile
                            ) { open(.connection) }
                        }
                    }
                    Spacer(minLength: 0)
                    if let receipt = sentGiftReceipt, receipt.roomID == room.id {
                        NanaSentRoomGiftBanner(receipt: receipt, avatarData: sessionStore.activeProfile?.avatarData)
                            .id(receipt.id)
                            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    }
                    if showsReplayActivity && !composerFocused {
                        NanaRoomReplayActivityView(
                            room: room, recordedMessages: messages,
                            audience: replayAudience, isActive: replayActivityIsActive,
                            hidesGiftEffects: sentGiftReceipt != nil,
                            isVoiceRoom: presentation == .voice
                        )
                            .id(room.id)
                    } else {
                        chatOverlay(maxHeight: geometry.size.height * (presentation == .voice ? 0.20 : 0.30))
                    }
                    roomComposer
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .allowsHitTesting(panel == nil && pendingGiftReceipt == nil)
                .accessibilityHidden(panel != nil || pendingGiftReceipt != nil)
                if let receipt = pendingGiftReceipt {
                    giftConfirmationOverlay(receipt)
                } else if let panel {
                    Color.clear.ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { self.panel = nil }
                        .accessibilityHidden(true)
                    if panel == .options {
                        optionsPanel
                            .frame(maxWidth: 340)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if panel == .more && presentation == .voice {
                        NanaMoreVoiceRoomsView(currentRoomID: room.id, selectRoom: { nextRoom in
                            guard contentStore.saveDraft(messageDraft, for: "live-room-\(room.id)") else { return }
                            self.panel = nil
                            room = nextRoom
                        }, close: { self.panel = nil })
                        .frame(height: geometry.size.height * 0.82)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if panel == .more || panel == .music {
                        roomPanel(panel, availableHeight: geometry.size.height)
                            .frame(width: panel == .music ? min(440, geometry.size.width * 0.9) : geometry.size.width * 0.8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        roomPanel(panel, availableHeight: geometry.size.height)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: panel)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: sentGiftReceipt?.id)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task(id: room.id) {
            cancelGiftConfirmation()
            sentGiftReceipt = nil
            voiceConnection.end()
            startPlayback()
            messageDraft = contentStore.draft(for: "live-room-\(room.id)")
            if room.id == "room-aurora" { await contentStore.refresh(.auroraRoom) }
        }
        .onDisappear {
            cancelGiftConfirmation()
            sentGiftReceipt = nil
            voiceConnection.end()
            _ = contentStore.saveDraft(messageDraft, for: "live-room-\(room.id)")
            stopPlayback()
        }
        .task(id: "\(room.id)-\(voiceConnection.sessionID)-\(voiceConnection.isActive)-\(scenePhase == .active)") {
            guard voiceConnection.isActive, scenePhase == .active else { return }
            let sessionID = voiceConnection.sessionID
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled, voiceConnection.isActive, voiceConnection.sessionID == sessionID else { return }
                voiceConnection.advance()
            }
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
            roomMusic.setMuted(muted)
        }
        .onChange(of: contentStore.safetyDismissalID) { _, _ in
            if !contentStore.isRoomVisible(room) { stopPlayback(); dismiss() }
        }
        .task(id: sentGiftReceipt?.id) {
            guard let receiptID = sentGiftReceipt?.id else { return }
            do { try await Task.sleep(for: .seconds(6)) }
            catch { return }
            guard !Task.isCancelled, sentGiftReceipt?.id == receiptID else { return }
            sentGiftReceipt = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isPlaying { player?.play() } else { player?.pause() }
            if phase != .active { roomMusic.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            roomMusic.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            roomMusic.pause()
        }
        .sheet(isPresented: $showingWallet) { NanaWalletView() }
        .fullScreenCover(item: $selectedProfile) { NanaUserProfileView(profile: $0) }
        .fullScreenCover(item: $conversation) { NanaConversationView(conversation: $0) }
        .alert("More coins needed", isPresented: $showingInsufficientCoins) {
            Button("Open Wallet") { showingWallet = true }
            Button("Cancel", role: .cancel) { }
        } message: { Text("You need \(giftTotal) coins. Your balance is \(coinStore.balance).") }
        .alert("Block this host?", isPresented: $showingBlockConfirmation) {
            Button("Block", role: .destructive) {
                if contentStore.blockPostAuthor(contentStore.discussion(for: room)) {
                    stopPlayback()
                    panel = nil
                    moderationSuccess = AccountEntryNotice(title: "User blocked", explanation: "\(room.hostName) and their related content are now hidden. Your choice has been saved.")
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This host and their rooms will be hidden on this device.") }
        .overlay {
            if let moderationSuccess {
                AccountConsentNotice(notice: moderationSuccess, dismissNotice: {
                    contentStore.completeSafetyAction()
                    dismiss()
                }, dimsBackground: false)
            } else if let notice = contentStore.actionNotice {
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
        HStack(spacing: 2) {
            Button { open(.host) } label: {
                HStack(spacing: 5) {
                    NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.hostName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(host.map { "\($0.age) · \($0.region) · Lv.\($0.level)" } ?? room.category)
                            .font(.system(size: 8)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 6).frame(height: 40)
                .background(.black.opacity(0.35), in: Capsule())
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View host information")
            Button { open(.audience) } label: {
                HStack(spacing: 5) {
                    HStack(spacing: -8) {
                        ForEach(audiencePortraits) { portrait in
                            NanaAvatarView(title: portrait.title, assetKey: portrait.assetKey, size: 24)
                        }
                    }
                    Text(contentStore.displayedViewerCount(for: room).formatted(.number.notation(.compactName)))
                        .font(.system(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
                }
                .padding(.horizontal, 6).frame(height: 32)
                .background(.black.opacity(0.3), in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Room audience, \(contentStore.displayedViewerCount(for: room))")
            .accessibilityHint(room.streamSourceType == "simulatedReplay" ? "Shows the complete sample audience" : "Shows available room members")
            headerControl("ellipsis", title: "Room options") { open(.options) }
            headerControl("xmark", title: "Leave room") { open(.exit) }
        }
    }

    private var roomStatusBar: some View {
        HStack(spacing: 4) {
            artworkButton("055", title: "Room ranking", size: 30) { open(.ranking) }
            Button { open(.heat) } label: {
                HStack(spacing: 3) {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_009", contentMode: .fit).frame(width: 14, height: 17)
                    Text("Room heat").font(.system(size: 9)).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 8))
                }.padding(.horizontal, 7).frame(height: 28)
                    .background(.black.opacity(0.3), in: Capsule())
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer(minLength: 4)
            Text(presentation == .voice ? "Voice room" : room.streamSourceType == "simulatedReplay" ? "Video replay" : room.roomState)
                .font(.system(size: 9, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 8).frame(height: 28)
                .background(.black.opacity(0.3), in: Capsule())
            Button { open(.more) } label: {
                HStack(spacing: 4) {
                    Text("More rooms").font(.system(size: 9, weight: .medium)).lineLimit(1)
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 8).frame(height: 28)
                .background(.black.opacity(0.3), in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("More rooms")
        }
    }

    private func headerControl(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.3), in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    private var voiceThemeBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(roomMusic.selectedTrack.map { "\($0.title) · \(roomMusic.isPlaying ? "Playing" : "Paused")" } ?? room.subtitle)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { open(.music) } label: {
                HStack(spacing: 5) {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_077", contentMode: .fit)
                        .frame(width: 22, height: 22)
                    Text("Music").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10).frame(height: 36)
                .background(NanaPalette.violet.opacity(0.35), in: Capsule())
                .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Music on demand")
        }
    }

    private var musicPanel: some View {
        NanaRoomMusicPanel(player: roomMusic)
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
        let isDrawer = panel == .more || panel == .music
        let footerHeight: CGFloat = panel == .gifts ? 78 : 0
        let heightFraction: CGFloat = (panel == .ranking || panel == .heat || panel == .audience || panel == .connection) ? 0.60 : 0.78
        let limit = max(80, availableHeight * heightFraction - 78 - footerHeight)
        let contentHeight = panelContentHeights[panel.rawValue] ?? initialPanelHeight(panel)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(panel.rawValue).font(.system(size: 16, weight: .heavy).italic())
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if panel == .connection && voiceConnection.phase == .connecting {
                    symbolButton(voiceConnection.microphoneMuted ? "mic.slash.fill" : "mic.fill",
                                 title: voiceConnection.microphoneMuted ? "Unmute microphone" : "Mute microphone") {
                        voiceConnection.microphoneMuted.toggle()
                    }
                    symbolButton(voiceConnection.cameraEnabled ? "video.fill" : "video.slash.fill",
                                 title: voiceConnection.cameraEnabled ? "Turn camera off" : "Turn camera on") {
                        voiceConnection.cameraEnabled.toggle()
                    }
                }
                if panel == .ranking || panel == .heat {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_\(panel == .heat ? "009" : "008")", contentMode: .fit)
                        .frame(width: 48, height: 40).accessibilityHidden(true)
                }
                symbolButton("xmark.circle", title: "Close panel") { self.panel = nil }
            }
            .frame(height: 44)
            ScrollView(showsIndicators: false) {
                panelContent(panel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: NanaRoomPanelHeightKey.self, value: content.size.height)
                        }
                    }
            }
            .frame(height: isDrawer ? max(80, availableHeight - 76) : min(contentHeight, limit))
            .onPreferenceChange(NanaRoomPanelHeightKey.self) { height in
                if height > 0 && abs((panelContentHeights[panel.rawValue] ?? 0) - height) > 1 {
                    panelContentHeights[panel.rawValue] = height
                }
            }
            if panel == .gifts { giftBalanceBar }
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 12)
        .accessibilityAction(.escape) { self.panel = nil }
        .background {
            Color(red: 0.065, green: 0.052, blue: 0.075)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func initialPanelHeight(_ panel: RoomPanel) -> CGFloat {
        switch panel {
        case .gifts: return 210
        case .exit: return 110
        case .connection: return 340
        case .ranking, .heat: return 360
        case .audience: return max(80, CGFloat(participants.count + replayAudience.count) * 60 + 80)
        case .host: return 300
        case .quick, .report: return 300
        default: return 180
        }
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
        case .report: reportPanel
        }
    }

    private var hostPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Button {
                selectedProfile = host
            } label: {
                HStack(spacing: 10) {
                    NanaAvatarView(title: room.hostName, assetKey: room.hostAvatarAssetKey, size: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(room.hostName).font(.system(size: 15, weight: .semibold))
                        Text(host.map { "\($0.region) · Lv.\($0.level)" } ?? room.category).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(host == nil)
            .accessibilityLabel("View \(room.hostName)'s profile")
            Text(host?.introduction ?? room.subtitle).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            HStack(spacing: 8) {
                metric("Follower", value: host.map { String($0.followerCount) } ?? "—", color: .green)
                metric("Following", value: host.map { String($0.followingCount) } ?? "—", color: .cyan)
                metric("Audience", value: String(audienceCount), color: .orange)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(room.title).font(.system(size: 14, weight: .medium))
                Text(room.subtitle).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                Button {
                    if let host { conversation = contentStore.conversation(for: host) }
                    else { contentStore.explainUnavailable("Host profile") }
                } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_125", contentMode: .fit).frame(height: 38)
                }.buttonStyle(.plain).frame(minHeight: 44).accessibilityLabel("Private message")
                followButton
            }
        }
    }

    private var audiencePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if presentation == .voice && room.streamSourceType == "simulatedReplay" {
                voiceAudiencePanel
            } else {
                if room.streamSourceType == "simulatedReplay" {
                    Text("Sample audience · \(audienceCount) viewers")
                        .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                    ForEach(replayAudience) { member in
                        audienceMemberRow(name: member.displayName, assetKey: member.avatarAssetKey, detail: "Viewer")
                    }
                    if replayAudience.isEmpty { panelNote("No sample viewers in this replay.") }
                } else {
                    Text("\(audienceCount) viewers").font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                    panelNote("The complete viewer list is not available yet.")
                }
                if !participants.isEmpty {
                    Text("On stage").font(.system(size: 11)).foregroundStyle(NanaPalette.electricLilac)
                        .padding(.top, 4)
                    ForEach(participants) { profile in
                        audienceMemberRow(
                            name: profile.displayName, assetKey: profile.avatarAssetKey,
                            detail: "\(profile.region) · Lv.\(profile.level)"
                        )
                    }
                }
            }
        }
    }

    private var voiceAudiencePanel: some View {
        let seats = contentStore.voiceRoomSeats(for: room).filter { $0.profileID != nil }
        let onStageIDs = Set(seats.compactMap(\.profileID))
        let listeners = replayAudience.filter { !onStageIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(audienceCount) guests + host")
                .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            Text("On stage · \(seats.count)").font(.system(size: 11)).foregroundStyle(NanaPalette.electricLilac)
            ForEach(seats) { seat in
                let profile = seat.profileID.flatMap { contentStore.profile(with: $0) }
                let member = replayAudience.first { $0.id == seat.profileID }
                let isHost = seat.profileID == room.hostID
                audienceMemberRow(
                    name: profile?.displayName ?? member?.displayName ?? seat.displayName ?? "Guest",
                    assetKey: profile?.avatarAssetKey ?? member?.avatarAssetKey ?? (isHost ? room.hostAvatarAssetKey : nil),
                    detail: isHost ? "Host" : (seat.isMuted ? "On microphone · Muted" : "On microphone")
                )
            }
            if !listeners.isEmpty {
                Text("Listening").font(.system(size: 11)).foregroundStyle(NanaPalette.electricLilac)
                    .padding(.top, 4)
                ForEach(listeners) { member in
                    audienceMemberRow(name: member.displayName, assetKey: member.avatarAssetKey, detail: "Listener")
                }
            }
        }
    }

    private func audienceMemberRow(name: String, assetKey: String?, detail: String) -> some View {
        HStack(spacing: 10) {
            NanaAvatarView(title: name, assetKey: assetKey, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
        }
        .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rankingPanel(isHeat: Bool) -> some View {
        let category: NanaRankingCategory = isHeat ? .popularity : (presentation == .voice ? .voiceRoom : .liveRoom)
        let entries = NanaRankingSamples.entries(for: category)
            .filter { !contentStore.hiddenAuthorIDs.contains($0.profileID) }
        let hostEntry = entries.first { $0.profileID == room.hostID }
        let previewHeat = 280 + Int(room.id.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 420)
        return VStack(alignment: .leading, spacing: 10) {
            roomRankingSummary(isHeat: isHeat, hostEntry: hostEntry, previewHeat: previewHeat)
            Text("Sample rankings")
                .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    roomRankingRow(entry)
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
                }
            }
        }
    }

    private func roomRankingSummary(isHeat: Bool, hostEntry: NanaRankingEntry?, previewHeat: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isHeat ? "\(previewHeat)/800" : hostEntry.map { "No. \($0.rank)" } ?? "Unranked")
                        .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Color(red: 1, green: 0.28, blue: 0.31))
                    Text(isHeat ? "Popularity target" : room.hostName)
                        .font(.system(size: 11)).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(spacing: 3) {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_009", contentMode: .fit)
                        .frame(width: 30, height: 32)
                    Text(hostEntry.map { $0.giftCount.formatted(.number.notation(.compactName)) } ?? "—")
                        .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
                }
            }
            if isHeat {
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(NanaPalette.neonPink)
                        .frame(width: geometry.size.width * CGFloat(previewHeat) / 800)
                }
                .frame(height: 4)
                .accessibilityLabel("Sample popularity: \(previewHeat) of 800")
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [Color(red: 0.33, green: 0.31, blue: 0.52), Color(red: 0.12, green: 0.11, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.15), lineWidth: 0.7))
    }

    private func roomRankingRow(_ entry: NanaRankingEntry) -> some View {
        HStack(spacing: 9) {
            roomRankingBadge(entry.rank).frame(width: 28)
            NanaAvatarView(title: entry.displayName, assetKey: entry.avatarAssetKey, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text("Lv.\(entry.level)")
                    .font(.system(size: 8, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(NanaPalette.violet, in: Capsule())
            }
            Spacer(minLength: 4)
            NanaAssetImage(assetKey: "nana.voice.voice_asset_009", contentMode: .fit)
                .frame(width: 12, height: 16).accessibilityHidden(true)
            Text(entry.giftCount.formatted(.number.notation(.compactName)))
                .font(.system(size: 10)).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 4).frame(height: 48)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func roomRankingBadge(_ rank: Int) -> some View {
        if (1...3).contains(rank) {
            let asset = rank == 1 ? "005" : rank == 2 ? "001" : "003"
            NanaAssetImage(assetKey: "nana.voice.voice_asset_\(asset)", contentMode: .fit)
                .frame(width: 23, height: 29).accessibilityLabel("Rank \(rank)")
        } else {
            Text("\(rank)").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
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
        NanaVoiceConnectionPanel(
            session: voiceConnection, soundMuted: $isMuted,
            audience: connectionAudience, account: sessionStore.activeProfile
        )
    }

    private var connectionAudience: [NanaReplayAudienceMember] {
        if !replayAudience.isEmpty { return replayAudience }
        return participants.filter { $0.id != room.hostID }.compactMap { profile in
            guard let avatar = profile.avatarAssetKey else { return nil }
            return NanaReplayAudienceMember(id: profile.id, displayName: profile.displayName, avatarAssetKey: avatar)
        }
    }

    private var giftPanel: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(gifts) { gift in
                Button { selectedGiftID = gift.id } label: {
                    VStack(spacing: 8) {
                        NanaAssetImage(assetKey: gift.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit)
                            .frame(width: 49, height: 49)
                            .frame(maxWidth: .infinity).frame(height: 65)
                            .background(selectedGift?.id == gift.id ? Color(red: 0.22, green: 0.10, blue: 0.42) : Color(red: 0.19, green: 0.18, blue: 0.20), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedGift?.id == gift.id ? NanaPalette.violet : .clear, lineWidth: 1))
                        HStack(spacing: 3) {
                            if gift.coinCost > 0 {
                                NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit)
                                    .frame(width: 11, height: 11)
                            }
                            Text(gift.coinCost == 0 ? "Free" : "\(gift.coinCost)")
                                .font(.system(size: 11))
                                .foregroundStyle(gift.coinCost == 0 ? Color.green : NanaPalette.mutedWhite)
                        }.frame(height: 16)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(gift.title), \(gift.coinCost == 0 ? "free" : "\(gift.coinCost) coins")")
                .accessibilityAddTraits(selectedGift?.id == gift.id ? [.isSelected] : [])
            }
        }
        .padding(.top, 3).padding(.bottom, 3)
    }

    private var giftBalanceBar: some View {
        VStack(spacing: 5) {
            HStack(spacing: 2) {
                Button { showingWallet = true } label: {
                    HStack(spacing: 6) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contentStore.preference("hideCoinBalance", default: false) ? "••••" : coinStore.balance.formatted()).font(.system(size: 12, weight: .medium))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("Balance").font(.system(size: 9)).foregroundStyle(NanaPalette.mutedWhite)
                        }
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel(contentStore.preference("hideCoinBalance", default: false) ? "Balance hidden. Open wallet" : "Balance \(coinStore.balance) coins. Open wallet")
                Spacer(minLength: 2)
                HStack(spacing: 0) {
                    quantityButton("minus.circle", title: "Decrease quantity", enabled: giftQuantity > 1) { giftQuantity -= 1 }
                    Text("\(giftQuantity)").font(.system(size: 12)).monospacedDigit().frame(minWidth: 17)
                    quantityButton("plus.circle", title: "Increase quantity", enabled: giftQuantity < 99) { giftQuantity += 1 }
                    Button {
                        if coinStore.balance < giftTotal { showingInsufficientCoins = true }
                        else { prepareGiftConfirmation() }
                    } label: {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_102", contentMode: .fit)
                            .frame(width: 40, height: 26).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Send selected gift")
                }.background(.black.opacity(0.85), in: Capsule())
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color(red: 0.19, green: 0.19, blue: 0.20), in: Capsule())
            Text(giftTotal == 0 ? "Free gift" : "Total: \(giftTotal) coins")
                .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
        }
    }

    private func quantityButton(_ symbol: String, title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(enabled ? 0.6 : 0.2))
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(title)
    }

    private var moreRoomsPanel: some View {
        let available = contentStore.payload.rooms.filter { $0.id != room.id && contentStore.isRoomVisible($0) }
        let filtered = available.filter { moreRoomCategory == "All" || $0.category == moreRoomCategory }
        let categories = ["All"] + Array(Set(available.map(\.category))).sorted()
        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { category in
                        Button { moreRoomCategory = category } label: {
                            Text(category).font(.system(size: 10)).lineLimit(1)
                                .padding(.horizontal, 12).frame(height: 24)
                                .background(moreRoomCategory == category ? NanaPalette.violet : .white.opacity(0.10), in: Capsule())
                                .frame(height: 44)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if filtered.isEmpty { panelNote("No other rooms in this category.") }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                ForEach(filtered) { other in
                    Button {
                        _ = contentStore.saveDraft(messageDraft, for: "live-room-\(room.id)")
                        panel = nil
                        room = other
                    } label: {
                        NanaRoomDrawerCard(room: other, isVoice: presentation == .voice)
                    }.buttonStyle(.plain)
                }
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Room options")
                .font(.system(size: 17, weight: .heavy).italic())
                .foregroundStyle(NanaPalette.warmWhite)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
                .padding(.top, 4)

            VStack(spacing: 8) {
                roomOptionRow("Report", symbol: "flag", tint: NanaPalette.electricLilac) {
                    open(.report)
                }
                roomOptionRow("Block", symbol: "person.slash", tint: NanaPalette.softPink) {
                    showingBlockConfirmation = true
                }
            }

            Button { panel = nil } label: {
                Text("Close")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NanaPalette.warmWhite)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(red: 0.075, green: 0.055, blue: 0.10), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { panel = nil }
    }

    private func roomOptionRow(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(title == "Block" ? tint : NanaPalette.warmWhite)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var reportPanel: some View {
        VStack(spacing: 8) {
            ForEach(["Harassment", "Hateful content", "Sexual content", "Spam or scam", "Other"], id: \.self) { reason in
                Button { reportReason = reason } label: {
                    HStack {
                        Text(reason).font(.system(size: 12))
                        Spacer()
                        Image(systemName: reportReason == reason ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reportReason == reason ? NanaPalette.violet : NanaPalette.mutedWhite)
                    }.padding(.horizontal, 12).frame(height: 44)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Button {
                if contentStore.reportContent(contentStore.discussion(for: room), reason: reportReason) {
                    panel = nil
                    stopPlayback()
                    moderationSuccess = AccountEntryNotice(title: "Report saved", explanation: "Your report has been saved. This room is now hidden from your lists.")
                }
            } label: {
                Text("Submit report").font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 44).background(NanaPalette.violet, in: Capsule())
            }.buttonStyle(.plain)
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
        if panel == .more { moreRoomCategory = "All" }
    }
    private func submitMessage(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = contentStore.saveDraft(text, for: "live-room-\(room.id)")
        contentStore.appendRoomMessage(roomID: room.id, body: text)
        composerFocused = false
    }
    private func giftConfirmationOverlay(_ receipt: NanaRoomGiftReceipt) -> some View {
        ZStack {
            Color.clear.ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { cancelGiftConfirmation() }.accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                giftConfirmationCard(receipt).padding(20)
                ScrollView(showsIndicators: false) {
                    giftConfirmationCard(receipt).padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func giftConfirmationCard(_ receipt: NanaRoomGiftReceipt) -> some View {
        NanaGiftConfirmationCard(
            receipt: receipt, hostAvatar: room.hostAvatarAssetKey ?? host?.avatarAssetKey,
            balance: coinStore.balance, errorMessage: giftConfirmationError,
            cancel: cancelGiftConfirmation, send: sendGift
        )
        .disabled(isSendingGift)
    }

    private func prepareGiftConfirmation() {
        guard let gift = selectedGift else { return }
        giftConfirmationError = nil
        pendingGiftAccountID = sessionStore.activeProfile?.localAccountScope
        pendingGiftReceipt = NanaRoomGiftReceipt(
            id: UUID().uuidString, roomID: room.id, hostName: room.hostName,
            senderName: sessionStore.activeProfile?.displayName ?? "You",
            gift: gift, quantity: giftQuantity, createdAt: Date()
        )
    }

    private func cancelGiftConfirmation() {
        guard !isSendingGift else { return }
        pendingGiftReceipt = nil
        pendingGiftAccountID = nil
        giftConfirmationError = nil
    }

    private func sendGift() {
        guard !isSendingGift, let receipt = pendingGiftReceipt, receipt.roomID == room.id else { return }
        guard let accountID = pendingGiftAccountID,
              accountID == sessionStore.activeProfile?.localAccountScope else {
            giftConfirmationError = NanaRoomGiftError.accountChanged.errorDescription
            return
        }
        isSendingGift = true
        defer { isSendingGift = false }
        do {
            try coinStore.sendRoomGift(receipt, accountID: accountID)
            pendingGiftReceipt = nil
            pendingGiftAccountID = nil
            giftConfirmationError = nil
            panel = nil
            giftQuantity = 1
            sentGiftReceipt = receipt
        } catch let error as NanaRoomGiftError {
            giftConfirmationError = error.errorDescription
        } catch {
            giftConfirmationError = "Couldn't save this gift. Your balance hasn't changed. Please try again."
        }
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
        roomMusic.stop()
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
    }
}

private struct NanaRoomPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A drawer card has its own compact type scale; full-size room artwork does not
/// fit a two-column drawer and causes both viewer counts and titles to wrap.
private struct NanaRoomDrawerCard: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    let room: NanaLiveRoom
    let isVoice: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                NanaMediaPreview(assetKey: (isVoice ? room.hostAvatarAssetKey : room.streamAssetKey) ?? room.hostAvatarAssetKey ?? "nana.voice.room_backdrop_01")
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.12), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Label(contentStore.displayedViewerCount(for: room).formatted(.number.notation(.compactName)), systemImage: "person.fill")
                            .font(.system(size: 8)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer(minLength: 0)
                        if !isVoice {
                            NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit)
                                .frame(width: 30, height: 12)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(room.category).font(.system(size: 8, weight: .medium)).lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(NanaPalette.violet.opacity(0.8), in: Capsule())
                    Text(room.hostName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(room.title).font(.system(size: 9)).lineLimit(1).foregroundStyle(.white.opacity(0.7))
                }.padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .aspectRatio(169.0 / 227.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(room.hostName), \(room.title), \(contentStore.displayedViewerCount(for: room)) viewers")
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
