import SwiftUI
import UIKit

struct YourShoreView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var showingEdit = false
    @State private var showingWallet = false
    @State private var showingCheckIn = false
    @State private var showingCollection = false
    @State private var collectionTitle = "Backpack"
    @State private var showingLevel = false
    @State private var showingFeedback = false
    @State private var showingConnections = false
    @State private var connectionCategory = "Friends"
    @State private var showingSettings = false
    @State private var showingBlacklist = false
    @State private var showingLogout = false

    private var localProfile: NanaProfile {
        NanaProfile(id: "profile-self", displayName: sessionStore.activeProfile?.displayName ?? "Nana member", handle: "nana.member", region: sessionStore.activeProfile?.country ?? "Not set", language: "Not set", gender: sessionStore.activeProfile?.gender ?? "Not set", age: Calendar.current.dateComponents([.year], from: sessionStore.activeProfile?.birthDate ?? Date(), to: Date()).year ?? 0, introduction: "Shape your profile with the places, people and moments you want to keep close.", avatarAssetKey: nil, isConnected: false, followerCount: 0, followingCount: 0, level: contentStore.payload.wallet.level)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                if contentStore.state(for: .wallet) == .loading && contentStore.payload.wallet.nextLevelPoints == 1 {
                    NanaScreenLoading(label: "Loading your shore")
                } else if case .failed(let error) = contentStore.state(for: .wallet), contentStore.payload.wallet.nextLevelPoints == 1 {
                    NanaErrorState(title: "Your profile is unavailable", detail: error.localizedDescription, actionTitle: "Retry") { Task { await contentStore.refresh(.wallet) } }
                } else { ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        profileCard
                        statsRow
                        checkInCard
                        balanceStrip
                        profileMenu
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 90)
                } }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await contentStore.refresh(.wallet)
                coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
            }
            .sheet(isPresented: $showingEdit) { NanaEditProfileView() }
            .sheet(isPresented: $showingWallet) { NanaWalletView() }
            .sheet(isPresented: $showingCheckIn) { NanaCheckInView() }
            .sheet(isPresented: $showingCollection) { NanaCollectionView(title: collectionTitle) }
            .sheet(isPresented: $showingLevel) { NanaLevelView() }
            .sheet(isPresented: $showingFeedback) { NanaFeedbackView() }
            .sheet(isPresented: $showingConnections) { NanaConnectionsView(profile: localProfile, initialTab: connectionCategory) }
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
        Text("My Profile")
            .font(.system(size: 19, weight: .heavy).italic())
            .foregroundStyle(NanaPalette.warmWhite)
            .frame(height: 36, alignment: .leading)
    }

    private var profileCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Button { showingEdit = true } label: {
                Group {
                    if let data = sessionStore.activeProfile?.avatarData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                    } else {
                        NanaAvatarView(title: localProfile.displayName, assetKey: localProfile.avatarAssetKey, size: 72)
                    }
                }
                .padding(3)
                .overlay(Circle().stroke(NanaPalette.violet, lineWidth: 1.5))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, NanaPalette.electricLilac)
                        .background(.white, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(localProfile.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NanaPalette.warmWhite)
                        .lineLimit(1)
                    Text("Lv.\(localProfile.level)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(colors: [Color.orange, NanaPalette.softPink, NanaPalette.violet, Color.cyan], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                        .fixedSize()
                }
                HStack(spacing: 7) {
                    if sessionStore.activeProfile?.birthDate != nil {
                        Text("\(localProfile.age)")
                    }
                    Text(localProfile.region.isEmpty ? "Not set" : localProfile.region)
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(NanaPalette.mutedWhite)
                Text(profileInterests)
                    .font(.system(size: 11))
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 7)

            Button { showingSettings = true } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_168", contentMode: .fit)
                    .frame(width: 29, height: 29)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .padding(.top, 3)
        }
    }

    private var profileInterests: String {
        let interests = sessionStore.activeProfile?.interests ?? []
        return interests.isEmpty ? "Add your interests to make this space yours." : interests.joined(separator: " · ")
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("Fans", value: "—", category: "Fans")
            stat("Friend", value: "\(contentStore.payload.profiles.filter { $0.isConnected && !contentStore.blockedProfileIDs.contains($0.id) }.count)", category: "Friends")
            stat("Follow", value: "\(contentStore.followedProfiles.count)", category: "Following")
            Spacer(minLength: 0)
        }
        .padding(.top, 5)
    }

    private func stat(_ title: String, value: String, category: String) -> some View {
        Button {
            connectionCategory = category
            showingConnections = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(NanaPalette.warmWhite)
                Text(title).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
            }
            .frame(width: 82, height: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("「 Sign in today 」")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NanaPalette.warmWhite)
                Spacer()
                Button { showingCheckIn = true } label: {
                    Group {
                        if contentStore.checkedInToday {
                            Text("Checked in")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 89, height: 25)
                                .background(NanaPalette.violet, in: Capsule())
                        } else {
                            NanaAssetImage(assetKey: "nana.voice.voice_asset_146", contentMode: .fit)
                                .frame(width: 89, height: 25)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(contentStore.checkedInToday ? "View check-in calendar" : "Check in")
            }
            HStack(spacing: 10) {
                ForEach(0..<10, id: \.self) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index - 9, to: Date()) ?? Date()
                    let checked = contentStore.personal.checkInDays.contains(contentStore.dayKey(date))
                    Circle()
                        .fill(checked ? NanaPalette.violet : Color.white.opacity(0.24))
                        .frame(width: 9, height: 9)
                        .overlay {
                            if index == 9 && checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(contentStore.personal.checkInDays.count) check-ins recorded")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 20) {
                    Text("Lv\(contentStore.activityLevel)")
                        .foregroundStyle(NanaPalette.warmWhite)
                    HStack(spacing: 0) {
                        Text("\(contentStore.activityPoints % 200)").foregroundStyle(NanaPalette.electricLilac)
                        Text("/200").foregroundStyle(NanaPalette.mutedWhite)
                    }
                }
                .font(.system(size: 11))
                GeometryReader { geometry in
                    let width = geometry.size.width * CGFloat(contentStore.activityPoints % 200) / 200
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.85))
                        Capsule().fill(NanaPalette.violet).frame(width: width)
                        Circle().fill(NanaPalette.violet)
                            .frame(width: 7, height: 7)
                            .offset(x: max(0, min(width - 3.5, geometry.size.width - 7)))
                    }
                }
                .frame(height: 4)
                .accessibilityLabel("Activity progress, \(contentStore.activityPoints % 200) of 200 points")
            }
            .padding(.top, 3)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Color(red: 0.39, green: 0.34, blue: 0.61).opacity(0.7), NanaPalette.deepSpace.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 0.7))
    }

    private var balanceStrip: some View {
        Button { showingWallet = true } label: {
            HStack(spacing: 8) {
                // The original strip already contains the coin artwork on its left edge.
                Color.clear.frame(width: 43, height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("My balance").font(.system(size: 13, weight: .medium))
                    Text(coinStore.balance.formatted()).font(.system(size: 11))
                }
                .foregroundStyle(NanaPalette.warmWhite)
                Spacer(minLength: 3)
                NanaAssetImage(assetKey: "nana.voice.voice_asset_106", contentMode: .fit)
                    .frame(width: 53, height: 26)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background {
                GeometryReader { geometry in
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_105")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("My balance, \(coinStore.balance) coins. Open wallet")
    }

    private var profileMenu: some View {
        VStack(spacing: 8) {
            menuRow(title: "Shop", icon: "storefront.fill") { collectionTitle = "Store"; showingCollection = true }
            menuRow(title: "Backpack", icon: "backpack.fill") { collectionTitle = "Backpack"; showingCollection = true }
            menuRow(title: "My level", icon: "diamond.fill") { showingLevel = true }
            menuRow(title: "Feedback", icon: "questionmark.bubble.fill") { showingFeedback = true }
            menuRow(title: "Blacklist", icon: "person.crop.circle.badge.xmark") { showingBlacklist = true }
            menuRow(title: "Log out", icon: "power", destructive: true) { showingLogout = true }
        }
    }

    private func menuRow(title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if destructive {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_023", contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NanaPalette.warmWhite)
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                Spacer()
                NanaAssetImage(assetKey: "nana.voice.voice_asset_033", contentMode: .fit)
                    .frame(width: 14, height: 20)
                    .opacity(0.9)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(NanaProfileMenuButtonStyle())
    }

}

private struct NanaProfileMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? NanaPalette.violet.opacity(0.3) : Color(white: 0.14),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.3 : 0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    @State private var selectedTab: String

    init(profile: NanaProfile, initialTab: String = "Friends") {
        self.profile = profile
        _selectedTab = State(initialValue: initialTab)
    }

    private var people: [NanaProfile] {
        contentStore.payload.profiles.filter { !contentStore.blockedProfileIDs.contains($0.id) }
    }

    private var visiblePeople: [NanaProfile] {
        switch selectedTab {
        case "Fans":
            // Profile popularity does not describe who follows the signed-in account.
            return []
        case "Following": return contentStore.followedProfiles
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
                            NanaEmptyState(
                                title: selectedTab == "Fans" ? "Fans are unavailable" : "Nothing here yet",
                                detail: selectedTab == "Fans" ? "Your fan list will appear when the service provides follower relationships." : "Your \(selectedTab.lowercased()) will appear here when there is something to show.",
                                actionTitle: nil, action: nil
                            )
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
    @EnvironmentObject private var coinStore: NanaCoinStore

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
                                Text("\(coinStore.balance)").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("coins").font(NanaType.caption).foregroundStyle(.white.opacity(0.72))
                            }
                            Spacer()
                            Image("NanaWalletArtwork").resizable().scaledToFit().frame(width: 145, height: 82)
                        }
                        .padding(18)
                        .background(LinearGradient(colors: [NanaPalette.warning.opacity(0.88), NanaPalette.neonPink.opacity(0.75), NanaPalette.electricLilac.opacity(0.82)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        NanaSectionTitle(eyebrow: "Recharge options", title: "Choose a pack")
                        VStack(spacing: 9) {
                            ForEach(NanaCoinStore.packs) { pack in
                                HStack(spacing: 12) {
                                    NanaAssetImage(assetKey: "nana.pic.Dc6Dfy6jSal", contentMode: .fit).frame(width: 42, height: 42)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(pack.coins.formatted())").font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                                        Text("coins").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await coinStore.purchase(pack: pack) }
                                    } label: {
                                        if coinStore.purchasingProductID == pack.productID {
                                            ProgressView().tint(.white).frame(minWidth: 52)
                                        } else if let product = coinStore.products.first(where: { $0.id == pack.productID }) {
                                            Text(product.displayPrice)
                                        } else {
                                            Text(pack.fallbackPrice)
                                        }
                                    }
                                    .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
                                    .disabled(coinStore.purchasingProductID != nil)
                                }
                                .padding(11)
                                .background(NanaPalette.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        NanaSectionTitle(eyebrow: "Coin map", title: "What uses coins")
                        VStack(alignment: .leading, spacing: 9) {
                            coinUseRow(title: "Room gifts", detail: "Send a gift to a live room host", cost: "18–128")
                            coinUseRow(title: "Room effects", detail: "Coming with a published write contract", cost: "—")
                            coinUseRow(title: "Chat", detail: "Messages never spend coins", cost: "Free")
                        }
                        .padding(14)
                        .nanaCard()
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .task {
                await contentStore.refresh(.wallet)
                coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
            }
            .overlay { if let notice = coinStore.notice { AccountConsentNotice(notice: notice) { coinStore.dismissNotice() } } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func coinUseRow(title: String, detail: String, cost: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: title == "Chat" ? "bubble.left.and.bubble.right" : "sparkles")
                .foregroundStyle(title == "Chat" ? NanaPalette.electricLilac : NanaPalette.neonPink)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite)
                Text(detail).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            Text(cost).font(NanaType.caption.weight(.bold)).foregroundStyle(NanaPalette.softPink)
        }
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
            .task { await contentStore.refresh(.gifts) }
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
    @State private var savedDraft = false
    var body: some View { NavigationStack { ZStack { NanaBackdrop(); VStack(alignment: .leading, spacing: 16) { Text("Send feedback").font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite); Text("Tell us what would make your next room better.").font(NanaType.body).foregroundStyle(NanaPalette.mutedWhite); TextEditor(text: $message).scrollContentBackground(.hidden).foregroundStyle(.white).frame(height: 160).padding(12).background(NanaPalette.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(NanaPalette.border)); Button("Save draft") { savedDraft = contentStore.saveDraft(message, for: "feedback") }.buttonStyle(NanaPrimaryButtonStyle()); if savedDraft { Text("Draft saved").font(NanaType.caption).foregroundStyle(NanaPalette.softPink) }; Text("Sending feedback will be available when the service accepts submissions.").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite); Spacer() }.padding(22) }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }.onAppear { message = contentStore.draft(for: "feedback") }.overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } } }.preferredColorScheme(.dark) }
}

struct NanaSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingPrivacy = false
    @State private var showingNotice = false
    @State private var showingAbout = false
    @State private var selectedPolicy: AccountPolicyDocument?

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
                            settingsRow("Clear cache", icon: "trash") { contentStore.clearCache() }
                        }
                        settingsGroup {
                            settingsRow("User Agreement", icon: "doc.text") { selectedPolicy = .userAgreement }
                            settingsRow("Privacy Policy", icon: "doc.plaintext") { selectedPolicy = .privacyPolicy }
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
            .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
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
    @EnvironmentObject private var contentStore: NanaContentStore
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
            .onAppear {
                privateInformation = contentStore.preference("privateInformation")
                displayStatus = contentStore.preference("displayStatus")
                allowMessages = contentStore.preference("allowMessages")
                allowVideoCalls = contentStore.preference("allowVideoCalls")
            }
            .onChange(of: privateInformation) { _, value in contentStore.setPreference("privateInformation", value: value) }
            .onChange(of: displayStatus) { _, value in contentStore.setPreference("displayStatus", value: value) }
            .onChange(of: allowMessages) { _, value in contentStore.setPreference("allowMessages", value: value) }
            .onChange(of: allowVideoCalls) { _, value in contentStore.setPreference("allowVideoCalls", value: value) }
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
    @EnvironmentObject private var contentStore: NanaContentStore
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
            .onAppear {
                allowNotifications = contentStore.preference("allowNotifications")
                likeAndFollow = contentStore.preference("likeAndFollow")
                liveReminder = contentStore.preference("liveReminder")
                videoReminder = contentStore.preference("videoReminder")
            }
            .onChange(of: allowNotifications) { _, value in contentStore.setPreference("allowNotifications", value: value) }
            .onChange(of: likeAndFollow) { _, value in contentStore.setPreference("likeAndFollow", value: value) }
            .onChange(of: liveReminder) { _, value in contentStore.setPreference("liveReminder", value: value) }
            .onChange(of: videoReminder) { _, value in contentStore.setPreference("videoReminder", value: value) }
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
    @State private var selectedPolicy: AccountPolicyDocument?

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
                    Button("User Agreement") { selectedPolicy = .userAgreement }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.cardStrong))
                    Button("Privacy Policy") { selectedPolicy = .privacyPolicy }.buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.cardStrong))
                    Spacer()
                }
                .padding(28)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
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
                                    Button("Show") { contentStore.unhide(profileID: profile.id) }
                                        .font(NanaType.caption.weight(.bold))
                                        .foregroundStyle(NanaPalette.electricLilac)
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
