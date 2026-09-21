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
    @State private var showingSettings = false
    @State private var showingBlacklist = false
    @State private var showingLogout = false

    private var localProfile: NanaProfile {
        NanaProfile(id: "profile-self", displayName: sessionStore.activeProfile?.displayName ?? "Nana member", handle: "nana.member", region: sessionStore.activeProfile?.country ?? "Not set", language: "Not set", gender: sessionStore.activeProfile?.gender ?? "Not set", age: Calendar.current.dateComponents([.year], from: sessionStore.activeProfile?.birthDate ?? Date(), to: Date()).year ?? 0, introduction: "Shape your profile with the places, people and moments you want to keep close.", avatarAssetKey: nil, isConnected: false, followerCount: 0, followingCount: 0, level: contentStore.payload.wallet.level)
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
                        profileHighlights
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
            .sheet(isPresented: $showingSettings) { NanaSettingsView() }
            .sheet(isPresented: $showingBlacklist) { NanaBlacklistView() }
            .alert("Leave Nana?", isPresented: $showingLogout) {
                Button("Log out", role: .destructive) { sessionStore.signOut() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can sign in again whenever you are ready.")
            }
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
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NanaPalette.warmWhite)
                    .frame(width: 38, height: 38)
                    .background(NanaPalette.cardStrong, in: Circle())
            }
            .buttonStyle(.plain)
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
            NanaAvatarView(title: localProfile.displayName, assetKey: localProfile.avatarAssetKey, size: 78)
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

    private var profileHighlights: some View {
        VStack(spacing: 12) {
            Button { showingCheckIn = true } label: {
                HStack(spacing: 13) {
                    Image("NanaCheckInArtwork")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 74, height: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sign in today")
                            .font(NanaType.bodyMedium)
                            .foregroundStyle(NanaPalette.warmWhite)
                        Text(contentStore.checkedInToday ? "Checked in" : "Keep your streak glowing")
                            .font(NanaType.caption)
                            .foregroundStyle(NanaPalette.mutedWhite)
                    }
                    Spacer()
                    Text(contentStore.checkedInToday ? "Done" : "Check-in")
                        .font(NanaType.caption.weight(.bold))
                        .foregroundStyle(NanaPalette.warmWhite)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(NanaPalette.violet, in: Capsule())
                }
                .padding(12)
                .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { showingWallet = true } label: {
                HStack(spacing: 12) {
                    Image("NanaWalletArtwork")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 66, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My balance")
                            .font(NanaType.bodyMedium)
                            .foregroundStyle(NanaPalette.warmWhite)
                        Text("\(contentStore.payload.wallet.coinBalance) coins")
                            .font(NanaType.caption)
                            .foregroundStyle(NanaPalette.mutedWhite)
                    }
                    Spacer()
                    Text("Check")
                        .font(NanaType.caption.weight(.bold))
                        .foregroundStyle(NanaPalette.deepSpace)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(NanaPalette.warmWhite, in: Capsule())
                }
                .padding(12)
                .background(LinearGradient(colors: [NanaPalette.warning.opacity(0.88), NanaPalette.neonPink.opacity(0.82), NanaPalette.electricLilac.opacity(0.92)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
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
            menuRow(title: "Black list", detail: "Hidden people and rooms", icon: "nosign") { showingBlacklist = true }
            menuRow(title: "Log out", detail: "Leave Nana", icon: "rectangle.portrait.and.arrow.right", destructive: true) { showingLogout = true }
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
    @State private var showingAlbum = false

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
                            Button { showingAlbum = true } label: {
                                HStack(spacing: 12) {
                                    NanaAssetImage(assetKey: "nana.pic.Dc0SA4UiUy3", contentMode: .fill)
                                        .frame(width: 78, height: 78)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Personal Album")
                                            .font(NanaType.bodyMedium)
                                            .foregroundStyle(NanaPalette.warmWhite)
                                        Text("View shared moments")
                                            .font(NanaType.caption)
                                            .foregroundStyle(NanaPalette.mutedWhite)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(NanaPalette.electricLilac)
                                }
                            }
                            .buttonStyle(.plain)
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
            .sheet(isPresented: $showingAlbum) { NanaAlbumGalleryView(profile: liveProfile) }
            .alert("Hide this profile?", isPresented: $showingReport) { Button("Hide", role: .destructive) { contentStore.block(profileID: liveProfile.id) }; Button("Cancel", role: .cancel) { } } message: { Text("This profile and its related activity will be hidden from your view.") }
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
    @State private var selectedTab = "Friends"

    private var people: [NanaProfile] {
        contentStore.payload.profiles.filter { !contentStore.blockedProfileIDs.contains($0.id) }
    }

    private var visiblePeople: [NanaProfile] {
        switch selectedTab {
        case "Fans": return people.sorted { $0.followerCount > $1.followerCount }
        case "Following": return people.sorted { $0.followingCount > $1.followingCount }
        default: return people.filter { $0.isConnected }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connections")
                            .font(NanaType.hero)
                            .foregroundStyle(NanaPalette.warmWhite)
                        HStack(spacing: 18) {
                            connectionTab("Fans")
                            connectionTab("Friends")
                            connectionTab("Following")
                            Spacer()
                        }
                        if visiblePeople.isEmpty {
                            NanaEmptyState(title: "Nothing here yet", detail: "Your \(selectedTab.lowercased()) will appear here when there is something to show.", actionTitle: nil, action: nil)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(visiblePeople) { person in
                                    NanaPersonRow(profile: person, trailingTitle: person.isConnected ? "Connected" : "Connect") {
                                        contentStore.toggleConnection(for: person.id)
                                    }
                                    .padding(.horizontal, 10)
                                    .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(profile.displayName)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }

    private func connectionTab(_ title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = title }
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .serif).italic())
                    .foregroundStyle(selectedTab == title ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
                Capsule()
                    .fill(selectedTab == title ? NanaPalette.neonPink : .clear)
                    .frame(width: 30, height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NanaWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    private let packs = [("123,1", "$9.99"), ("246,2", "$19.99"), ("512,0", "$39.99"), ("1,280", "$79.99")]

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Wallet").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                            Spacer()
                            Image(systemName: "questionmark.circle").foregroundStyle(NanaPalette.mutedWhite)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("My balance").font(NanaType.caption).foregroundStyle(.white.opacity(0.82))
                                Text("\(contentStore.payload.wallet.coinBalance)").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("coins").font(NanaType.caption).foregroundStyle(.white.opacity(0.72))
                            }
                            Spacer()
                            Image("NanaWalletArtwork").resizable().scaledToFit().frame(width: 145, height: 82)
                        }
                        .padding(18)
                        .background(LinearGradient(colors: [NanaPalette.warning.opacity(0.88), NanaPalette.neonPink.opacity(0.75), NanaPalette.electricLilac.opacity(0.82)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        NanaSectionTitle(eyebrow: "Recharge options", title: "Choose a pack")
                        VStack(spacing: 9) {
                            ForEach(packs, id: \.0) { pack in
                                HStack(spacing: 12) {
                                    NanaAssetImage(assetKey: "nana.pic.Dc6Dfy6jSal", contentMode: .fit).frame(width: 42, height: 42)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pack.0).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                                        Text("coins").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                                    }
                                    Spacer()
                                    Button(pack.1) { contentStore.explainUnavailable("Coin recharge") }
                                        .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
                                }
                                .padding(11)
                                .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Daily check-in").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                            Spacer()
                            Text("June 2026").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        }
                        HStack(spacing: 12) {
                            Image("NanaCheckInArtwork").resizable().scaledToFit().frame(width: 118, height: 92)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(contentStore.checkedInToday ? "Checked in today" : "Sign in today").font(NanaType.section).foregroundStyle(NanaPalette.warmWhite)
                                Text("Keep your rhythm and collect activity points.").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                            }
                        }
                        .padding(15)
                        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        HStack(spacing: 7) {
                            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                                VStack(spacing: 7) {
                                    Text(day).font(.system(size: 9, weight: .semibold)).foregroundStyle(NanaPalette.mutedWhite)
                                    Circle().fill(day == "Wed" ? NanaPalette.violet : NanaPalette.cardStrong).frame(width: 28, height: 28).overlay { if day == "Wed" { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(14)
                        .nanaCard()
                        Button(contentStore.checkedInToday ? "Checked in" : "Clock in") { contentStore.performCheckIn() }
                            .buttonStyle(NanaPrimaryButtonStyle(tint: contentStore.checkedInToday ? NanaPalette.cardStrong : NanaPalette.violet))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(22)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .task { await contentStore.refresh(.gifts) }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaCollectionView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text(title).font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                        Text(title == "Store" ? "Small things for the rooms you keep." : "Your collected room items.")
                            .font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        if contentStore.payload.gifts.isEmpty {
                            NanaEmptyState(title: "No items to show", detail: "The collection catalog is not available yet.", actionTitle: nil, action: nil)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(contentStore.payload.gifts) { gift in
                                    VStack(spacing: 7) {
                                        NanaAssetImage(assetKey: gift.assetKey ?? "nana.pic.Dc6Dfy6jSal", contentMode: .fit).frame(height: 62)
                                        Text(gift.title).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(NanaPalette.warmWhite).lineLimit(1)
                                        Text(title == "Store" ? "\(gift.coinCost) coins" : "Collected").font(.system(size: 9, design: .rounded)).foregroundStyle(NanaPalette.softPink)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 106)
                                    .padding(8)
                                    .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                        if title == "Store" {
                            Button("Buy") { contentStore.explainUnavailable("Buying items") }.buttonStyle(NanaPrimaryButtonStyle())
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaLevelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("My level").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                                Text("Lv.\(contentStore.payload.wallet.level)").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                                Text("Progress updates with your Nana rhythm.").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                            }
                            Spacer()
                            Image("NanaLevelGem").resizable().scaledToFit().frame(width: 124, height: 104)
                        }
                        .padding(17)
                        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity progress").font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                            ProgressView(value: Double(contentStore.payload.wallet.activityPoints), total: Double(max(contentStore.payload.wallet.nextLevelPoints, 1))).tint(NanaPalette.neonPink)
                            Text("\(contentStore.payload.wallet.activityPoints) / \(contentStore.payload.wallet.nextLevelPoints) points").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                        }
                        .padding(17)
                        .background(LinearGradient(colors: [NanaPalette.warning.opacity(0.82), NanaPalette.neonPink.opacity(0.7), NanaPalette.electricLilac.opacity(0.85)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                        HStack(spacing: 9) {
                            levelMetric("Spent", "\(contentStore.payload.wallet.totalSpent)")
                            levelMetric("Activity", "\(contentStore.payload.wallet.activityPoints)")
                            levelMetric("Room", "\(contentStore.payload.wallet.roomContribution)")
                        }
                    }
                    .padding(22)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }

    private func levelMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(NanaPalette.warmWhite)
            Text(title).font(.system(size: 9, design: .rounded)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct NanaFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var message = ""
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(alignment: .leading, spacing: 16) { Text("Send feedback").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text("Tell us what would make your next room better.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite); TextEditor(text: $message).scrollContentBackground(.hidden).foregroundStyle(.white).frame(height: 160).padding(12).background(NanaPalette.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(NanaPalette.border)); Button("Submit") { contentStore.explainUnavailable("Feedback") }.buttonStyle(NanaPrimaryButtonStyle()); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }.overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } } }.preferredColorScheme(.dark) }
}

struct NanaSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingPrivacy = false
    @State private var showingNotice = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Settings").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                        settingsGroup {
                            settingsRow("Account security", icon: "lock.shield") { contentStore.explainUnavailable("Account security") }
                            settingsRow("Add account", icon: "person.badge.plus") { contentStore.explainUnavailable("Adding accounts") }
                        }
                        settingsGroup {
                            settingsRow("Privacy settings", icon: "hand.raised") { showingPrivacy = true }
                            settingsRow("Notice", icon: "bell") { showingNotice = true }
                            settingsRow("Clear cache", icon: "trash") { contentStore.explainUnavailable("Clearing cache") }
                        }
                        settingsGroup {
                            settingsRow("User Agreement", icon: "doc.text") { contentStore.explainUnavailable("User Agreement") }
                            settingsRow("Privacy Policy", icon: "doc.plaintext") { contentStore.explainUnavailable("Privacy Policy") }
                            settingsRow("About Nana", icon: "info.circle") { showingAbout = true }
                        }
                        .foregroundStyle(NanaPalette.warmWhite)
                    }
                    .padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(isPresented: $showingPrivacy) { NanaPrivacySettingsView() }
            .sheet(isPresented: $showingNotice) { NanaNoticeSettingsView() }
            .sheet(isPresented: $showingAbout) { NanaAboutView() }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func settingsGroup(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 14)
            .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func settingsRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(NanaPalette.electricLilac).frame(width: 23)
                Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(NanaPalette.mutedWhite)
            }
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }
}

private struct NanaPrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var privateInformation = true
    @State private var displayStatus = true
    @State private var allowMessages = true
    @State private var allowVideoCalls = true

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy settings").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                    privacyCard(title: "Private information", isOn: $privateInformation)
                    privacyCard(title: "Display status", isOn: $displayStatus)
                    privacyCard(title: "Allow messages", isOn: $allowMessages)
                    privacyCard(title: "Allow video calls", isOn: $allowVideoCalls)
                    Spacer()
                }
                .padding(20)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }

    private func privacyCard(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(NanaPalette.violet)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct NanaNoticeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var allowNotifications = true
    @State private var likeAndFollow = true
    @State private var liveReminder = true
    @State private var videoReminder = true

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Notice").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                    noticeToggle("Allow notifications", value: $allowNotifications)
                    noticeToggle("Like and follow", value: $likeAndFollow)
                    noticeToggle("Live broadcast reminder", value: $liveReminder)
                    noticeToggle("Video call reminder", value: $videoReminder)
                    Spacer()
                }
                .padding(20)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }

    private func noticeToggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
            Spacer()
            Toggle("", isOn: value).labelsHidden().tint(NanaPalette.violet)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct NanaAboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(spacing: 16) {
                    Image("NanaBrandIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text("Nana").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                    Text("A little room for the people and moments you keep close.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center)
                    Text("Version 1.0").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                    Button("User Agreement") { contentStore.explainUnavailable("User Agreement") }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.cardStrong))
                    Button("Privacy Policy") { contentStore.explainUnavailable("Privacy Policy") }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.cardStrong))
                    Spacer()
                }
                .padding(28)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaBlacklistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore

    private var blockedProfiles: [NanaProfile] {
        contentStore.payload.profiles.filter { contentStore.blockedProfileIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Blacklist").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                        if blockedProfiles.isEmpty {
                            NanaEmptyState(title: "Your blacklist is empty", detail: "Profiles you hide will appear here.", actionTitle: nil, action: nil)
                        } else {
                            ForEach(blockedProfiles) { profile in
                                HStack(spacing: 11) {
                                    NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.displayName).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                                        Text("Hidden from your rooms, posts and conversations").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                                    }
                                    Spacer()
                                    Image(systemName: "nosign").foregroundStyle(NanaPalette.warning)
                                }
                                .padding(12)
                                .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }
}
