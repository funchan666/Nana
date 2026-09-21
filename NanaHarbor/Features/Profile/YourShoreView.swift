import SwiftUI

struct YourShoreView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var mockStore: NanaMockStore
    @State private var showingEdit = false
    @State private var showingWallet = false
    @State private var showingCheckIn = false
    @State private var showingCollection = false
    @State private var collectionTitle = "Backpack"
    @State private var showingLevel = false
    @State private var showingFeedback = false
    @State private var showingConnections = false

    private var localProfile: NanaProfile {
        NanaProfile(id: "local", displayName: sessionStore.activeProfile?.displayName ?? "Nana member", handle: "nana.member", region: sessionStore.activeProfile?.country ?? "Not set", language: "English", gender: sessionStore.activeProfile?.gender ?? "Not set", age: 26, introduction: "A new voice in the room.", avatarAssetKey: nil, isConnected: true, followerCount: 128, followingCount: 64, level: mockStore.payload.wallet.level)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        profileCard
                        statsRow
                        albumStrip
                        profileMenu
                    }
                    .padding(.horizontal, NanaPalette.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEdit) { NanaEditProfileView() }
            .sheet(isPresented: $showingWallet) { NanaWalletView() }
            .sheet(isPresented: $showingCheckIn) { NanaCheckInView() }
            .sheet(isPresented: $showingCollection) { NanaCollectionView(title: collectionTitle) }
            .sheet(isPresented: $showingLevel) { NanaLevelView() }
            .sheet(isPresented: $showingFeedback) { NanaFeedbackView() }
            .sheet(isPresented: $showingConnections) { NanaConnectionsView(profile: localProfile) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("MY PROFILE")
                    .font(NanaType.stamp)
                    .tracking(1.4)
                    .foregroundStyle(NanaPalette.softPink)
                Text("Your corner of Nana")
                    .font(NanaType.hero)
                    .foregroundStyle(NanaPalette.warmWhite)
            }
            Spacer()
            Button { showingEdit = true } label: {
                Text("Edit")
                    .font(NanaType.caption.weight(.bold))
                    .foregroundStyle(NanaPalette.electricLilac)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(NanaPalette.cardStrong, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var profileCard: some View {
        HStack(alignment: .center, spacing: 14) {
            NanaPlaceholderPortrait(title: localProfile.displayName, size: 78)
            VStack(alignment: .leading, spacing: 7) {
                Text(localProfile.displayName)
                    .font(NanaType.section)
                    .foregroundStyle(NanaPalette.warmWhite)
                Text("@\(localProfile.handle)")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.electricLilac)
                Text("\(localProfile.region) · Lv.\(localProfile.level)")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            Image("NanaLevelGem")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
        }
        .padding(16)
        .nanaCard()
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("Followers", value: "\(localProfile.followerCount)")
            Divider().frame(height: 34).overlay(NanaPalette.border)
            stat("Friends", value: "\(localProfile.followingCount)")
            Divider().frame(height: 34).overlay(NanaPalette.border)
            stat("Level", value: "Lv.\(localProfile.level)")
        }
        .padding(.vertical, 15)
        .nanaCard()
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
            Text(title).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
        }
        .frame(maxWidth: .infinity)
    }

    private var albumStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            NanaSectionTitle(eyebrow: "Private album", title: "Friends can see these")
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [NanaPalette.violet.opacity(0.75), NanaPalette.neonPink.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Text("\(index + 1)").font(NanaType.section).foregroundStyle(.white.opacity(0.75)))
                        .frame(height: 86)
                }
            }
            Text("Album visibility: friends only")
                .font(NanaType.caption)
                .foregroundStyle(NanaPalette.mutedWhite)
        }
    }

    private var profileMenu: some View {
        VStack(spacing: 0) {
            menuRow(title: "Friends & connections", detail: "Your shared circle", icon: "person.2") { showingConnections = true }
            menuRow(title: "My wallet", detail: "\(mockStore.payload.wallet.coinBalance) coins", icon: "circle.grid.2x2.fill") { showingWallet = true }
            menuRow(title: "Daily check-in", detail: mockStore.checkedInToday ? "Checked in today" : "Claim today's signal", icon: "calendar.badge.plus") { showingCheckIn = true }
            menuRow(title: "Store", detail: "Gifts and room items", icon: "bag") { collectionTitle = "Store"; showingCollection = true }
            menuRow(title: "Backpack", detail: "Your collected items", icon: "shippingbox") { collectionTitle = "Backpack"; showingCollection = true }
            menuRow(title: "My level", detail: "Consumption · activity · room contribution", icon: "diamond.fill") { showingLevel = true }
            menuRow(title: "Feedback", detail: "Tell us what would make Nana better", icon: "text.bubble") { showingFeedback = true }
            menuRow(title: "Black list", detail: "Hidden people and rooms", icon: "nosign") { }
            menuRow(title: "Log out", detail: "End this local session", icon: "rectangle.portrait.and.arrow.right", destructive: true) { sessionStore.signOut() }
        }
        .padding(.horizontal, 14)
        .nanaCard()
    }

    private func menuRow(title: String, detail: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.electricLilac)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(NanaType.bodyMedium).foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                    Text(detail).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(NanaPalette.mutedWhite)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

struct NanaUserProfileView: View {
    let profile: NanaProfile
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mockStore: NanaMockStore
    @State private var showingCall = false
    @State private var showingConversation = false
    @State private var showingReport = false

    private var liveProfile: NanaProfile { mockStore.profile(with: profile.id) ?? profile }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        NanaPlaceholderPortrait(title: liveProfile.displayName, size: 108)
                        Text(liveProfile.displayName).font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                        Text("@\(liveProfile.handle) · \(liveProfile.region)").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        Text(liveProfile.introduction).font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center).padding(.horizontal, 16)
                        HStack(spacing: 10) {
                            Button(liveProfile.isConnected ? "Connected" : "Connect") { mockStore.toggleConnection(for: liveProfile.id) }
                                .buttonStyle(NanaPrimaryButtonStyle(tint: liveProfile.isConnected ? NanaPalette.cardStrong : NanaPalette.violet))
                            Button { showingCall = true } label: { Label("Video", systemImage: "video.fill") }
                                .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.neonPink))
                        }
                        HStack(spacing: 0) { stat("Followers", "\(liveProfile.followerCount)"); stat("Following", "\(liveProfile.followingCount)"); stat("Level", "Lv.\(liveProfile.level)") }
                            .padding(.vertical, 15).nanaCard()
                        VStack(alignment: .leading, spacing: 11) {
                            NanaSectionTitle(eyebrow: "Private album", title: "Friends only")
                            if liveProfile.isConnected {
                                ForEach(0..<4, id: \.self) { index in RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [NanaPalette.violet.opacity(0.8), NanaPalette.deepSpace], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 100).overlay(Text("Photo \(index + 1)").font(NanaType.caption).foregroundStyle(.white.opacity(0.7))) }
                            } else {
                                NanaEmptyState(title: "Connect to view this album", detail: "This album is visible to friends only.", actionTitle: nil, action: nil)
                            }
                        }
                        .padding(16).nanaCard()
                        HStack {
                            Button("Private message") { showingConversation = true }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.neonPink))
                            Button("Report") { showingReport = true }.foregroundStyle(NanaPalette.mutedWhite)
                        }
                    }
                    .padding(22)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(isPresented: $showingCall) { NanaVideoCallView(profile: liveProfile) }
            .sheet(isPresented: $showingConversation) {
                NanaConversationView(conversation: NanaConversation(id: "conversation-\(liveProfile.id)", profileID: liveProfile.id, displayName: liveProfile.displayName, preview: "Start a private conversation.", sentAtLabel: "now", unreadCount: 0, avatarAssetKey: nil))
            }
            .alert("Report this profile?", isPresented: $showingReport) { Button("Report", role: .destructive) { mockStore.block(profileID: liveProfile.id) }; Button("Cancel", role: .cancel) { } } message: { Text("The local mock hides this profile from messages, rooms and search.") }
        }
        .preferredColorScheme(.dark)
    }

    private func stat(_ title: String, _ value: String) -> some View { VStack(spacing: 5) { Text(value).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite); Text(title).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite) }.frame(maxWidth: .infinity) }
}

private struct NanaEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var displayName = ""
    @State private var country = ""

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(alignment: .leading, spacing: 17) {
                    Text("Edit profile").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                    TextField("Your name", text: $displayName).foregroundStyle(.white).nanaGlassField()
                    TextField("Country or region", text: $country).foregroundStyle(.white).nanaGlassField()
                    Button("Save") {
                        sessionStore.updateActiveProfile(displayName: displayName, country: country)
                        dismiss()
                    }
                    .buttonStyle(NanaPrimaryButtonStyle())
                    .padding(.top, 6)
                    Spacer()
                }
                .padding(22)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .onAppear { displayName = sessionStore.activeProfile?.displayName ?? ""; country = sessionStore.activeProfile?.country ?? "" }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaConnectionsView: View {
    let profile: NanaProfile
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mockStore: NanaMockStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView { VStack(alignment: .leading, spacing: 14) { Text("Connections").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); ForEach(mockStore.payload.profiles) { person in NanaPersonRow(profile: person, trailingTitle: person.isConnected ? "Connected" : "Connect") { mockStore.toggleConnection(for: person.id) } } }.padding(20) }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mockStore: NanaMockStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(alignment: .leading, spacing: 20) {
                    Text("My wallet").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("Balance").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite); Text("\(mockStore.payload.wallet.coinBalance)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white); Text("coins").font(NanaType.caption).foregroundStyle(NanaPalette.softPink) }; Spacer(); Image("NanaWalletArtwork").resizable().scaledToFit().frame(width: 150, height: 80) }.padding(18).nanaCard()
                    NanaSectionTitle(eyebrow: "Recharge", title: "Choose a coin pack")
                    ForEach(0..<3, id: \.self) { index in
                        let title = ["A small signal", "Room energy", "A bright night"][index]
                        let amount = [300, 800, 1800][index]
                        HStack { VStack(alignment: .leading) { Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite); Text("Local purchase placeholder").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite) }; Spacer(); Text("\(amount) coins").font(NanaType.caption.weight(.bold)).foregroundStyle(NanaPalette.electricLilac) }.padding(15).nanaCard()
                    }
                    Text("Purchases are represented locally until the real purchase service is approved.").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                    Spacer()
                }
                .padding(20)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mockStore: NanaMockStore
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(spacing: 18) { Image("NanaCheckInArtwork").resizable().scaledToFit().frame(height: 140); Text("Daily check-in").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text(mockStore.checkedInToday ? "You already left today's signal." : "Leave a small signal and earn activity points.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center); Button(mockStore.checkedInToday ? "Checked in" : "Check in") { mockStore.performCheckIn() }.buttonStyle(NanaPrimaryButtonStyle(tint: mockStore.checkedInToday ? NanaPalette.cardStrong : NanaPalette.violet)); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}

private struct NanaCollectionView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(alignment: .leading, spacing: 18) { Text(title).font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(0..<9, id: \.self) { index in VStack(spacing: 8) { Image("NanaGiftArtwork").resizable().scaledToFit().frame(height: 58); Text(index.isMultiple(of: 2) ? "Lumen" : "Room token").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite) }.frame(maxWidth: .infinity, minHeight: 105).nanaCard() } }; Spacer() }.padding(20) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}

private struct NanaLevelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mockStore: NanaMockStore
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(spacing: 16) { Image("NanaLevelGem").resizable().scaledToFit().frame(height: 130); Text("Level \(mockStore.payload.wallet.level)").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text("Consumption · activity · room contribution").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite); ProgressView(value: Double(mockStore.payload.wallet.activityPoints), total: Double(mockStore.payload.wallet.nextLevelPoints)).tint(NanaPalette.neonPink).padding(.horizontal, 18); Text("\(mockStore.payload.wallet.activityPoints) / \(mockStore.payload.wallet.nextLevelPoints) points").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}

private struct NanaFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(alignment: .leading, spacing: 16) { Text("Send feedback").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text("Tell us what would make your next room better.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite); TextEditor(text: $message).scrollContentBackground(.hidden).foregroundStyle(.white).frame(height: 160).padding(12).background(NanaPalette.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(NanaPalette.border)); Button("Submit") { dismiss() }.buttonStyle(NanaPrimaryButtonStyle()); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}
