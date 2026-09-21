import SwiftUI

struct YourShoreView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingEdit = false
    @State private var showingWallet = false
    @State private var showingCheckIn = false
    @State private var showingCollection = false
    @State private var collectionTitle = "Backpack"
    @State private var showingLevel = false
    @State private var showingFeedback = false
    @State private var showingConnections = false

    private var localProfile: NanaProfile {
        NanaProfile(id: "local", displayName: sessionStore.activeProfile?.displayName ?? "Nana member", handle: "nana.member", region: sessionStore.activeProfile?.country ?? "Not set", language: "Not set", gender: sessionStore.activeProfile?.gender ?? "Not set", age: Calendar.current.dateComponents([.year], from: sessionStore.activeProfile?.birthDate ?? Date(), to: Date()).year ?? 0, introduction: "Your profile details are stored on this device until a profile service is connected.", avatarAssetKey: nil, isConnected: false, followerCount: 0, followingCount: 0, level: contentStore.payload.wallet.level)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                if contentStore.state(for: .wallet) == .loading && contentStore.payload.wallet.nextLevelPoints == 1 {
                    NanaScreenLoading(label: "Loading your shore")
                } else if case .failed(let error) = contentStore.state(for: .wallet), contentStore.payload.wallet.nextLevelPoints == 1 {
                    NanaErrorState(title: "Your profile is unavailable", detail: error.localizedDescription, actionTitle: "Retry") { Task { await contentStore.refresh(.wallet) } }
                } else { ScrollView(showsIndicators: false) {
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
                } }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await contentStore.refresh(.wallet) }
            .sheet(isPresented: $showingEdit) { NanaEditProfileView() }
            .sheet(isPresented: $showingWallet) { NanaWalletView() }
            .sheet(isPresented: $showingCheckIn) { NanaCheckInView() }
            .sheet(isPresented: $showingCollection) { NanaCollectionView(title: collectionTitle) }
            .sheet(isPresented: $showingLevel) { NanaLevelView() }
            .sheet(isPresented: $showingFeedback) { NanaFeedbackView() }
            .sheet(isPresented: $showingConnections) { NanaConnectionsView(profile: localProfile) }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
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
            NanaSectionTitle(eyebrow: "Private album", title: "Album unavailable")
            NanaEmptyState(title: "No album service is connected", detail: "The published A-side contract has no album endpoint.", actionTitle: nil, action: nil)
        }
    }

    private var profileMenu: some View {
        VStack(spacing: 0) {
            menuRow(title: "Friends & connections", detail: "Your shared circle", icon: "person.2") { showingConnections = true }
            menuRow(title: "My wallet", detail: "\(contentStore.payload.wallet.coinBalance) coins", icon: "circle.grid.2x2.fill") { showingWallet = true }
            menuRow(title: "Daily check-in", detail: contentStore.checkedInToday ? "Checked in today" : "Claim today's signal", icon: "calendar.badge.plus") { showingCheckIn = true }
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
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingCall = false
    @State private var showingReport = false

    private var liveProfile: NanaProfile { contentStore.profile(with: profile.id) ?? profile }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        NanaAvatarView(title: liveProfile.displayName, assetKey: liveProfile.avatarAssetKey, size: 108)
                        Text(liveProfile.displayName).font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                        Text("@\(liveProfile.handle) · \(liveProfile.region)").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        Text(liveProfile.introduction).font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center).padding(.horizontal, 16)
                        HStack(spacing: 10) {
                            Button(liveProfile.isConnected ? "Connected" : "Connect") { contentStore.toggleConnection(for: liveProfile.id) }
                                .buttonStyle(NanaPrimaryButtonStyle(tint: liveProfile.isConnected ? NanaPalette.cardStrong : NanaPalette.violet))
                            Button { showingCall = true } label: { Label("Video", systemImage: "video.fill") }
                                .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.neonPink))
                        }
                        HStack(spacing: 0) { stat("Followers", "\(liveProfile.followerCount)"); stat("Following", "\(liveProfile.followingCount)"); stat("Level", "Lv.\(liveProfile.level)") }
                            .padding(.vertical, 15).nanaCard()
                        VStack(alignment: .leading, spacing: 11) {
                            NanaSectionTitle(eyebrow: "Private album", title: "Friends only")
                            NanaEmptyState(title: "Album unavailable", detail: "The published A-side contract has no album endpoint.", actionTitle: nil, action: nil)
                        }
                        .padding(16).nanaCard()
                        HStack {
                            Button("Private message") { contentStore.explainUnavailable("Private messages") }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.neonPink))
                            Button("Report") { showingReport = true }.foregroundStyle(NanaPalette.mutedWhite)
                        }
                    }
                    .padding(22)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(isPresented: $showingCall) { NanaVideoCallView(profile: liveProfile) }
            .alert("Hide this profile on this device?", isPresented: $showingReport) { Button("Hide", role: .destructive) { contentStore.block(profileID: liveProfile.id) }; Button("Cancel", role: .cancel) { } } message: { Text("This only changes what you see here. No report or server action is submitted.") }
            .task { if liveProfile.id == "profile-ava" { await contentStore.refresh(.avaProfile) } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
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
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView { VStack(alignment: .leading, spacing: 14) { Text("Connections").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); ForEach(contentStore.payload.profiles) { person in NanaPersonRow(profile: person, trailingTitle: person.isConnected ? "Connected" : "Connect") { contentStore.toggleConnection(for: person.id) } } }.padding(20) }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(alignment: .leading, spacing: 20) {
                    Text("My wallet").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                    HStack { VStack(alignment: .leading, spacing: 4) { Text("Balance").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite); Text("\(contentStore.payload.wallet.coinBalance)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white); Text("coins").font(NanaType.caption).foregroundStyle(NanaPalette.softPink) }; Spacer(); Image("NanaWalletArtwork").resizable().scaledToFit().frame(width: 150, height: 80) }.padding(18).nanaCard()
                    NanaSectionTitle(eyebrow: "Recharge", title: "Coin packs are unavailable")
                    NanaEmptyState(title: "No purchase service is connected", detail: "The published A-side contract provides a balance read only. Nothing can be charged from this screen.", actionTitle: nil, action: nil)
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
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(spacing: 18) { Image("NanaCheckInArtwork").resizable().scaledToFit().frame(height: 140); Text("Daily check-in").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text(contentStore.checkedInToday ? "You already left today's signal." : "Leave a small signal and earn activity points.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center); Button(contentStore.checkedInToday ? "Checked in" : "Check in") { contentStore.performCheckIn() }.buttonStyle(NanaPrimaryButtonStyle(tint: contentStore.checkedInToday ? NanaPalette.cardStrong : NanaPalette.violet)); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}

private struct NanaCollectionView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(alignment: .leading, spacing: 18) { Text(title).font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); NanaEmptyState(title: "Collection is unavailable", detail: "The published A-side contract has no collection or inventory endpoint.", actionTitle: nil, action: nil); Spacer() }.padding(20) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}

private struct NanaLevelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(spacing: 16) { Image("NanaLevelGem").resizable().scaledToFit().frame(height: 130); Text("Level \(contentStore.payload.wallet.level)").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text("Consumption · activity · room contribution").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite); ProgressView(value: Double(contentStore.payload.wallet.activityPoints), total: Double(contentStore.payload.wallet.nextLevelPoints)).tint(NanaPalette.neonPink).padding(.horizontal, 18); Text("\(contentStore.payload.wallet.activityPoints) / \(contentStore.payload.wallet.nextLevelPoints) points").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } } }.preferredColorScheme(.dark) }
}

private struct NanaFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var message = ""
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(alignment: .leading, spacing: 16) { Text("Send feedback").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text("Tell us what would make your next room better.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite); TextEditor(text: $message).scrollContentBackground(.hidden).foregroundStyle(.white).frame(height: 160).padding(12).background(NanaPalette.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(NanaPalette.border)); Button("Submit") { contentStore.explainUnavailable("Feedback") }.buttonStyle(NanaPrimaryButtonStyle()); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }.overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } } }.preferredColorScheme(.dark) }
}
