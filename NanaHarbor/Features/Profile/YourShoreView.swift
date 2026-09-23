import SwiftUI
import PhotosUI
import UIKit
import ImageIO

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
        NanaProfile(id: "profile-self", displayName: sessionStore.activeProfile?.displayName ?? "Nana member", handle: "nana.member", region: sessionStore.activeProfile?.country ?? "Not set", language: "Not set", gender: sessionStore.activeProfile?.gender ?? "Not set", age: Calendar.current.dateComponents([.year], from: sessionStore.activeProfile?.birthDate ?? Date(), to: Date()).year ?? 0, introduction: "Shape your profile with the places, people and moments you want to keep close.", avatarAssetKey: nil, isConnected: false, followerCount: 0, followingCount: 0, level: contentStore.activityLevel)
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
            .fullScreenCover(isPresented: $showingEdit) { NanaEditProfileView() }
            .fullScreenCover(isPresented: $showingWallet) { NanaWalletView() }
            .fullScreenCover(isPresented: $showingCheckIn) { NanaCheckInView() }
            .fullScreenCover(isPresented: $showingCollection) { NanaCollectionView(title: collectionTitle) }
            .fullScreenCover(isPresented: $showingLevel) { NanaLevelView() }
            .fullScreenCover(isPresented: $showingFeedback) { NanaFeedbackView() }
            .fullScreenCover(isPresented: $showingConnections) { NanaConnectionsView(profile: localProfile, initialTab: connectionCategory) }
            .fullScreenCover(isPresented: $showingSettings) { NanaSettingsView() }
            .fullScreenCover(isPresented: $showingBlacklist) { NanaBlacklistView() }
            .sheet(isPresented: $showingLogout) {
                NanaProfileActionSheet(title: "Log out?", detail: "Your saved profile and photos will be here when you sign in again.", actionTitle: "Confirm exit",
                                       secondaryTitle: "Switch accounts", secondaryAction: { sessionStore.signOut() }) {
                    sessionStore.signOut()
                }
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
                NanaAccountAvatarView(data: sessionStore.activeProfile?.avatarData, size: 72)
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
        if let signature = sessionStore.activeProfile?.introduction, !signature.isEmpty { return signature }
        let interests = sessionStore.activeProfile?.interests ?? []
        return interests.isEmpty ? "Add your interests to make this space yours." : interests.joined(separator: " · ")
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("Followers", value: "\(contentStore.accountFollowers.count)", category: "Followers")
            stat("Following", value: "\(contentStore.followedProfiles.count)", category: "Following")
            stat("Friends", value: "\(contentStore.mutualFriends.count)", category: "Friends")
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
    @State private var safetyAction: NanaPostSafetyAction?
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
                        }
                        NanaPostSafetyButtons(subject: "profile") { safetyAction = $0 }
                    }
                    .padding(22)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(isPresented: $showingCall) { NanaVideoCallView(profile: liveProfile) }
            .fullScreenCover(isPresented: $showingAlbum) { NanaAlbumGalleryView(profile: liveProfile) }
            .sheet(item: $safetyAction) { action in
                NanaPostSafetySheet(context: contentStore.discussion(for: profile), initialAction: action) { dismiss() }
            }
            .onChange(of: contentStore.safetyDismissalID) { _, _ in
                if contentStore.hiddenAuthorIDs.contains(profile.id) { dismiss() }
            }
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
    @State private var gender = ""
    @State private var birthDate: Date?
    @State private var selectedInterests = Set<String>()
    @State private var introduction = ""
    @State private var avatarData: Data?
    @State private var resetAvatar = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var editingAccountScope: String?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var showingDate = false
    @State private var chosenDate = Date()
    private var interestOptions: [String] {
        Array(Set(["Music", "Live chat", "Creative", "Travel", "Gaming", "Late night", "Art", "Open talk"]
                  + (sessionStore.activeProfile?.interests ?? []) + Array(selectedInterests))).sorted()
    }

    var body: some View {
        NanaProfilePage("Edit profile") {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    avatarPicker
                    lineField("Nickname", placeholder: "Please enter", value: $displayName)
                    dateField
                    lineField("Country", placeholder: "Country or region", value: $country)
                    genderField
                    interestsField
                    lineField("Signature", placeholder: "A little about you", value: $introduction)
                        .onChange(of: introduction) { _, value in if value.count > 160 { introduction = String(value.prefix(160)) } }
                }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save", action: save)
                .buttonStyle(NanaPrimaryButtonStyle())
                .disabled(loadingPhoto || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 40).padding(.vertical, 16)
                .background(.black.opacity(0.86))
        }
        .onAppear(perform: loadProfile)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            loadingPhoto = true
            photoError = nil
            Task { @MainActor in await loadPhoto(item) }
        }
        .sheet(isPresented: $showingDate) {
            VStack(spacing: 16) {
                Text("Date of birth").font(.system(size: 20, weight: .bold))
                DatePicker("Date of birth", selection: $chosenDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden().tint(NanaPalette.violet)
                Button("Done") { birthDate = chosenDate; showingDate = false }
                    .buttonStyle(NanaPrimaryButtonStyle())
            }.padding(24).presentationDetents([.height(350)])
                .presentationBackground(NanaPalette.deepSpace).preferredColorScheme(.dark)
        }
        .overlay {
            if let notice = sessionStore.sessionNotice {
                AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil }
            }
        }
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldTitle("Set avatar")
            HStack {
                Spacer()
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    NanaAccountAvatarView(data: avatarData, size: 126)
                        .overlay(alignment: .bottom) {
                            Image(systemName: "camera.fill").font(.system(size: 18))
                                .foregroundStyle(.white).frame(width: 38, height: 38)
                                .background(NanaPalette.violet, in: Circle()).offset(y: 8)
                        }
                }.disabled(loadingPhoto).accessibilityLabel("Choose avatar")
                    .overlay(alignment: .topTrailing) {
                        if avatarData != nil {
                            Button { avatarData = nil; resetAvatar = true } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).offset(x: 17, y: -15).accessibilityLabel("Reset avatar")
                        }
                    }
                Spacer()
            }
            if loadingPhoto { ProgressView().tint(NanaPalette.violet).frame(maxWidth: .infinity) }
            if let photoError { Text(photoError).font(.system(size: 12)).foregroundStyle(NanaPalette.warning) }
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
    }

    private func lineField(_ title: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle(title)
            HStack(spacing: 8) {
                TextField(placeholder, text: value).font(.system(size: 14))
                if !value.wrappedValue.isEmpty {
                    Button { value.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.orange)
                            .frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Clear \(title)")
                }
            }.frame(minHeight: 44)
            Rectangle().fill(NanaPalette.border).frame(height: 0.5)
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle("Date of Birth")
            Button {
                chosenDate = birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
                showingDate = true
            } label: {
                HStack {
                    Text(birthDate?.formatted(date: .numeric, time: .omitted) ?? "Choose date").font(.system(size: 14))
                    Spacer()
                    Image(systemName: "chevron.right.circle").foregroundStyle(NanaPalette.mutedWhite)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain)
            Rectangle().fill(NanaPalette.border).frame(height: 0.5)
        }
    }

    private var genderField: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldTitle("Gender")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(["Male", "Female", "Non-binary", "Prefer not to say"], id: \.self) { option in
                    Button { gender = option } label: {
                        Text(option).font(.system(size: 12))
                            .foregroundStyle(gender == option ? NanaPalette.electricLilac : NanaPalette.mutedWhite)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(Capsule().stroke(gender == option ? NanaPalette.violet : NanaPalette.border))
                    }.buttonStyle(.plain).accessibilityAddTraits(gender == option ? .isSelected : [])
                }
            }
        }
    }

    private var interestsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldTitle("Label")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                ForEach(interestOptions, id: \.self) { interest in
                    Button {
                        if !selectedInterests.insert(interest).inserted { selectedInterests.remove(interest) }
                    } label: {
                        Text("# \(interest)").font(.system(size: 11)).lineLimit(1)
                            .foregroundStyle(selectedInterests.contains(interest) ? NanaPalette.electricLilac : NanaPalette.mutedWhite)
                            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 32)
                            .overlay(Capsule().stroke(selectedInterests.contains(interest) ? NanaPalette.violet : NanaPalette.border))
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedInterests.contains(interest) ? .isSelected : [])
                }
            }
        }
    }

    private func loadProfile() {
        guard editingAccountScope == nil, let profile = sessionStore.activeProfile else { return }
        editingAccountScope = profile.localAccountScope
        displayName = profile.displayName; country = profile.country; gender = profile.gender
        birthDate = profile.birthDate; selectedInterests = Set(profile.interests)
        avatarData = profile.avatarData; introduction = profile.introduction ?? ""
    }

    private func save() {
        guard let editingAccountScope else { return }
        if sessionStore.updateActiveProfile(displayName: displayName, country: country, avatarData: avatarData,
                                           accountScope: editingAccountScope, gender: gender, birthDate: birthDate,
                                           interests: selectedInterests.sorted(), introduction: introduction, resetAvatar: resetAvatar) {
            dismiss()
        }
    }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { loadingPhoto = false; selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), data.count <= 25_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024
                  ] as CFDictionary), let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8) else {
                photoError = "Choose a photo smaller than 25 MB."; return
            }
            guard editingAccountScope == sessionStore.activeProfile?.localAccountScope else { return }
            avatarData = jpeg; resetAvatar = false
        } catch { photoError = "Couldn't load this photo. Please try another one." }
    }
}

private struct NanaProfilePage<Content: View>: View {
    let title: String
    let help: (() -> Void)?
    let content: Content
    @EnvironmentObject private var contentStore: NanaContentStore

    init(_ title: String, help: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaTabBackdrop()
                VStack(spacing: 0) {
                    NanaDetailPageHeader(title: title, trailingSymbol: "questionmark.circle", trailingLabel: "About \(title)", trailingAction: help)
                    content
                }
            }
            .foregroundStyle(NanaPalette.warmWhite)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if let notice = contentStore.actionNotice {
                    AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct NanaProfileActionSheet: View {
    let title: String
    let detail: String
    let actionTitle: String
    var destructive = true
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 23, weight: .bold))
            Text(detail).font(.system(size: 14)).foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
                action()
            } label: {
                Text(actionTitle).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(NanaPalette.deepSpace, in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
            if let secondaryTitle, let secondaryAction {
                Button {
                    dismiss()
                    secondaryAction()
                } label: {
                    Text(secondaryTitle).font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(NanaPalette.deepSpace, in: RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain)
            }
            Button { dismiss() } label: {
                Text("Close").font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(24)
        .presentationDetents([.height(secondaryTitle == nil ? 320 : 390), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color(red: 0.075, green: 0.055, blue: 0.105))
    }
}

private struct NanaProfileHelpSheet: View {
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 23, weight: .bold))
            ScrollView {
                Text(message).font(.system(size: 14)).lineSpacing(5)
                    .foregroundStyle(NanaPalette.mutedWhite)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Got it") { dismiss() }.buttonStyle(NanaPrimaryButtonStyle())
        }
        .padding(24).foregroundStyle(NanaPalette.warmWhite)
        .presentationDetents([.height(330), .large])
        .presentationDragIndicator(.visible).presentationCornerRadius(28)
        .presentationBackground(NanaPalette.deepSpace)
    }
}

private struct NanaRelationshipCard: View {
    let profile: NanaProfile
    var blocked = false
    let action: () -> Void
    @EnvironmentObject private var contentStore: NanaContentStore

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let asset = profile.avatarAssetKey { NanaAssetImage(assetKey: asset) }
                else { NanaAvatarView(title: profile.displayName, assetKey: nil, size: 64) }
            }
            .frame(width: 66, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NanaPalette.violet, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(profile.age) · \(profile.region) · Lv.\(profile.level)")
                        .font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                    if !blocked && contentStore.liveFriendRooms.contains(where: { $0.hostID == profile.id }) {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_053", contentMode: .fit).frame(width: 28, height: 11)
                    }
                }
                Text(blocked ? "Hidden from your feed and rooms" : profile.introduction)
                    .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                VStack(spacing: 3) {
                    if !blocked {
                        Text("Check").font(.system(size: 9, weight: .bold).italic())
                            .foregroundStyle(.black).padding(.horizontal, 7)
                            .background(Color.green, in: Capsule())
                    }
                    Image(systemName: blocked ? "trash" : "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(NanaPalette.violet, in: RoundedRectangle(cornerRadius: 11))
                }.frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(blocked ? "Unblock \(profile.displayName)" : "View \(profile.displayName)")
        }
        .padding(12)
        .background(NanaPalette.deepSpace, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct NanaConnectionsView: View {
    let profile: NanaProfile
    let initialTab: String
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var selectedPerson: NanaProfile?

    private var people: [NanaProfile] {
        switch initialTab {
        case "Followers": return contentStore.accountFollowers
        case "Following": return contentStore.followedProfiles
        default: return contentStore.mutualFriends
        }
    }

    var body: some View {
        NanaProfilePage(initialTab) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if people.isEmpty {
                        NanaEmptyState(title: "No \(initialTab.lowercased()) yet", detail: "Your \(initialTab.lowercased()) will appear here.", actionTitle: nil, action: nil)
                            .padding(.top, 64)
                    }
                    ForEach(people) { person in
                        NanaRelationshipCard(profile: person) { selectedPerson = person }
                    }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .fullScreenCover(item: $selectedPerson) { NanaUserProfileView(profile: $0) }
    }
}

struct NanaWalletView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var showingHelp = false

    var body: some View {
        NanaProfilePage("Wallet", help: { showingHelp = true }) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: -22) {
                    balanceCard
                        .padding(.horizontal, 20)
                    rechargeOptions
                }
                .padding(.top, 8)
            }
        }
        .task {
            await contentStore.refresh(.wallet)
            coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
        }
        .sheet(isPresented: $showingHelp) {
            NanaProfileHelpSheet(title: "Your Nana wallet", message: "Coins can be used for room gifts. Free gifts do not reduce your balance.\n\nRecharge purchases are confirmed through the App Store. The price shown by Apple at checkout applies. Coins are added after the purchase has been verified.")
        }
        .overlay {
            if let notice = coinStore.notice { AccountConsentNotice(notice: notice) { coinStore.dismissNotice() } }
        }
    }

    private var balanceCard: some View {
        Color.clear.aspectRatio(700.0 / 260.0, contentMode: .fit)
            .background(Image("NanaWalletArtwork").resizable().scaledToFit())
            .overlay {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My balance").font(.system(size: 17, weight: .medium))
                        Text(coinStore.balance.formatted())
                            .font(.system(size: 14)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("coins").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                    }
                    // Reserve both illustrated sides of the supplied balance artwork.
                    .frame(width: geometry.size.width * 0.46, alignment: .leading)
                    .padding(.leading, geometry.size.width * 0.25)
                    .padding(.top, geometry.size.height * 0.17)
                }
            }
    }

    private var rechargeOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recharge options")
                .font(.system(size: 15, weight: .medium))
            VStack(spacing: 12) {
                ForEach(NanaCoinStore.packs) { pack in packRow(pack) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The reference's list surface overlaps the lower edge of the banner.
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.28), location: 0),
                .init(color: Color.black.opacity(0.80), location: 0.11),
                .init(color: .black, location: 0.32)
            ], startPoint: .top, endPoint: .bottom)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        }
    }

    private func packRow(_ pack: NanaCoinPack) -> some View {
        HStack(spacing: 12) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.coins.formatted()).font(.system(size: 18, weight: .medium))
                Text("coins").font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 8)
            Button { Task { await coinStore.purchase(pack: pack) } } label: {
                Group {
                    if coinStore.purchasingProductID == pack.productID { ProgressView().tint(.white) }
                    else { Text(coinStore.products.first(where: { $0.id == pack.productID })?.displayPrice ?? pack.fallbackPrice) }
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 15).frame(minWidth: 74, minHeight: 30)
                .background(
                    pack.id == NanaCoinStore.packs.first?.id
                        ? Color(red: 1, green: 0.39, blue: 0)
                        : NanaPalette.violet,
                    in: Capsule()
                )
                .frame(minHeight: 44)
            }.buttonStyle(.plain).disabled(coinStore.purchasingProductID != nil)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minHeight: 72)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct NanaCheckInView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var monthOffset = 0
    @State private var showingHelp = false
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var month: Date {
        let today = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return calendar.date(byAdding: .month, value: monthOffset, to: start) ?? start
    }
    private var days: [Date] {
        let offset = (calendar.component(.weekday, from: month) + 5) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month),
              let monthDays = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let cellCount = ((offset + monthDays.count + 6) / 7) * 7
        return (0..<cellCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var monthTitle: String {
        String(format: "%04d/%02d", calendar.component(.year, from: month), calendar.component(.month, from: month))
    }

    var body: some View {
        NanaProfilePage("Daily check-in", help: { showingHelp = true }) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Keep the binding rings and calendar character at their original proportions.
                    Image("NanaCheckInArtwork")
                        .resizable().scaledToFit()
                        .accessibilityHidden(true)
                        .overlay {
                            GeometryReader { geometry in
                                let heroHeight = geometry.size.width * 430 / 700
                                VStack(spacing: 0) {
                                    hero(width: geometry.size.width)
                                        .frame(height: heroHeight)
                                    calendarCard(height: geometry.size.height - heroHeight)
                                }
                            }
                        }
                    rewardSummary
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingHelp) {
            NanaProfileHelpSheet(title: "Daily check-in", message: "Check in once each day to collect 10 activity points. Your marked days are saved on this device for your account.\n\nCheck-in is free. Past dates can be viewed in the calendar; they cannot be checked in retroactively.")
        }
    }

    private func hero(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                Text(contentStore.checkedInToday ? "Checked in today" : "「 Sign in today 」")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    Text("Lv.\(contentStore.activityLevel)")
                    (Text("\(contentStore.activityPoints % 200)").foregroundColor(NanaPalette.softPink) + Text("/200"))
                }.font(.system(size: 11))
                activityProgress
                Button { contentStore.performCheckIn() } label: {
                    Label(contentStore.checkedInToday ? "Checked in" : "Check-in", systemImage: "calendar.badge.checkmark")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 14).frame(height: 29)
                        .background(NanaPalette.violet, in: Capsule())
                        .frame(minHeight: 44)
                }
                    .buttonStyle(.plain).disabled(contentStore.checkedInToday)
            }
            .frame(width: width * 0.40, alignment: .leading)
            .padding(.leading, width * 0.075)
            Spacer(minLength: 0)
        }
        .padding(.top, width * 0.035)
    }

    private var activityProgress: some View {
        GeometryReader { geometry in
            let progress = CGFloat(contentStore.activityPoints % 200) / 200
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.85))
                Capsule().fill(NanaPalette.violet).frame(width: geometry.size.width * progress)
                Circle().fill(NanaPalette.violet).frame(width: 9, height: 9)
                    .offset(x: max(0, (geometry.size.width - 9) * progress))
            }
        }.frame(height: 4)
            .accessibilityLabel("Activity progress, \(contentStore.activityPoints % 200) of 200 points")
    }

    private func calendarCard(height: CGFloat) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        let rowCount = max(1, days.count / 7)
        let dayHeight = max(24, (height - 180) / CGFloat(rowCount))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                monthButton("chevron.left.circle.fill", label: "Previous month", offset: -1)
                Text(monthTitle).font(.system(size: 15)).monospacedDigit()
                monthButton("chevron.right.circle.fill", label: "Next month", offset: 1)
            }.frame(maxWidth: .infinity)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day).font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite).frame(height: 22)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days, id: \.self) { date in dayCell(date).frame(height: dayHeight) }
            }
            Spacer(minLength: 12)
            Button { contentStore.performCheckIn() } label: {
                ZStack {
                    Text(contentStore.checkedInToday ? "Checked in" : "Clock in")
                        .font(.system(size: 14, weight: .semibold))
                    HStack {
                        Spacer()
                        Text("+10 pts").font(.system(size: 10))
                    }.padding(.horizontal, 14)
                }
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(NanaPalette.violet, in: Capsule())
            }
            .buttonStyle(.plain).disabled(contentStore.checkedInToday)
            .opacity(contentStore.checkedInToday ? 0.6 : 1)
            .padding(.horizontal, 16)
            .accessibilityLabel(contentStore.checkedInToday ? "Checked in today" : "Clock in, receive 10 activity points")
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 18)
        .frame(height: height)
    }

    private func monthButton(_ symbol: String, label: String, offset: Int) -> some View {
        Button { monthOffset += offset } label: {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(offset < 0 ? NanaPalette.violet : .white.opacity(0.6))
                .frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func dayCell(_ date: Date) -> some View {
        let checked = contentStore.personal.checkInDays.contains(contentStore.dayKey(date))
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.19, green: 0.20, blue: 0.21))
            if checked {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(NanaPalette.violet)
            } else {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12))
                    .foregroundStyle(calendar.isDateInToday(date) ? NanaPalette.softPink : .white.opacity(inMonth ? 0.8 : 0.25))
            }
        }
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(checked ? "checked in" : "not checked in")")
    }

    private var rewardSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 25)).foregroundStyle(Color.cyan.opacity(0.85))
                .frame(width: 34)
                .accessibilityHidden(true)
            Text("A little progress, every day")
                .font(.system(size: 12)).foregroundStyle(Color(red: 0.35, green: 0.77, blue: 0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("Free").font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 17).padding(.vertical, 8)
                .background(Color(red: 0.28, green: 0.72, blue: 0.91), in: Capsule())
        }
        .padding(12)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NanaCollectionView: View {
    let title: String
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var coinStore: NanaCoinStore
    @State private var selectedGiftID = NanaGift.roomCatalog[0].id
    @State private var quantity = 1
    private var selectedGift: NanaGift { NanaGift.roomCatalog.first { $0.id == selectedGiftID } ?? NanaGift.roomCatalog[0] }
    private var isStore: Bool { title == "Store" }

    var body: some View {
        NanaProfilePage(title) {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 24) {
                    ForEach(NanaGift.roomCatalog) { gift in giftTile(gift) }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
                if !isStore {
                    Text("Free gifts are ready to use in rooms.")
                        .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite).padding(20)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if isStore { purchaseBar } }
    }

    private func giftTile(_ gift: NanaGift) -> some View {
        Button { selectedGiftID = gift.id } label: {
            VStack(spacing: 10) {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { NanaAssetImage(assetKey: gift.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit).padding(10) }
                    .background(selectedGiftID == gift.id ? NanaPalette.violet.opacity(0.32) : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(selectedGiftID == gift.id ? NanaPalette.violet : .clear, lineWidth: 1.5))
                HStack(spacing: 3) {
                    if isStore && gift.coinCost > 0 {
                        NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 12, height: 12)
                    }
                    Text(gift.coinCost == 0 ? "Free" : isStore ? "\(gift.coinCost)" : "× 0")
                        .font(.system(size: 12)).foregroundStyle(gift.coinCost == 0 ? .green : NanaPalette.mutedWhite)
                }
            }
        }.buttonStyle(.plain).accessibilityLabel("\(gift.title), \(gift.coinCost == 0 ? "Free" : "\(gift.coinCost) coins")")
    }

    private var purchaseBar: some View {
        HStack(spacing: 8) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(coinStore.balance.formatted()).font(.system(size: 14, weight: .medium))
                Text("Balance").font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { quantity = max(1, quantity - 1) } label: { Image(systemName: "minus.circle").frame(width: 36, height: 44) }
                    .disabled(quantity == 1).accessibilityLabel("Decrease quantity")
                Text("\(quantity)").font(.system(size: 13)).monospacedDigit().frame(minWidth: 20)
                Button { quantity = min(99, quantity + 1) } label: { Image(systemName: "plus.circle").frame(width: 36, height: 44) }
                    .disabled(quantity == 99).accessibilityLabel("Increase quantity")
                Button { contentStore.explainUnavailable("Buying items") } label: {
                    Text("Buy").font(.system(size: 13, weight: .medium)).padding(.horizontal, 14)
                        .frame(height: 32).background(NanaPalette.violet, in: Capsule())
                }.frame(minHeight: 44)
            }
            .buttonStyle(.plain).padding(.horizontal, 5).background(.black, in: Capsule())
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(12).background(Color(white: 0.18), in: Capsule())
        .overlay(alignment: .top) {
            Text(selectedGift.coinCost == 0 ? "Free gift" : "Total: \(selectedGift.coinCost * quantity) coins")
                .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).offset(y: -22)
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12).background(.black.opacity(0.9))
    }
}

private struct NanaLevelView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        NanaProfilePage("My level") {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("My level").font(.system(size: 16, weight: .semibold))
                            Text("Lv.\(contentStore.activityLevel)").font(.system(size: 30, weight: .bold))
                            Text("Grow with daily check-ins.").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                        }
                        Spacer()
                        Image("NanaLevelGem").resizable().scaledToFit().frame(width: 140, height: 118)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Days checked in").font(.system(size: 13))
                        Label("\(contentStore.personal.checkInDays.count)", systemImage: "calendar.badge.checkmark")
                            .font(.system(size: 27, weight: .semibold))
                        ProgressView(value: Double(contentStore.activityPoints % 200), total: 200).tint(.white)
                        Text("Next level: \(contentStore.activityPoints % 200)/200 points")
                            .font(.system(size: 12))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.orange, NanaPalette.neonPink, NanaPalette.violet, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20))
                }.padding(20)
            }
        }
    }
}

private struct NanaFeedbackView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var topic = ""
    @State private var message = ""
    @State private var loaded = false
    @FocusState private var focused: Bool
    private var canSubmit: Bool { !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NanaProfilePage("Feedback") {
            ScrollView {
                VStack(spacing: 14) {
                    TextField("Please enter the question topic", text: $topic)
                        .font(.system(size: 14)).padding(15).focused($focused)
                        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: topic) { _, value in if value.count > 80 { topic = String(value.prefix(80)) } }
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Please enter the details of the question").font(.system(size: 14))
                                .foregroundStyle(NanaPalette.mutedWhite).padding(.horizontal, 19).padding(.top, 22)
                        }
                        TextEditor(text: $message).scrollContentBackground(.hidden)
                            .font(.system(size: 14)).padding(14).focused($focused).frame(height: 190)
                    }
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: message) { _, value in if value.count > 2000 { message = String(value.prefix(2000)) } }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Submit") {
                focused = false
                if contentStore.saveFeedback(topic: topic, message: message) { topic = ""; message = "" }
            }
            .buttonStyle(NanaPrimaryButtonStyle()).disabled(!canSubmit).opacity(canSubmit ? 1 : 0.45)
            .padding(.horizontal, 44).padding(.vertical, 22)
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            topic = contentStore.draft(for: "feedback.topic")
            message = contentStore.draft(for: "feedback")
        }
    }
}

private struct NanaSettingsRow: View {
    let title: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 14))
                    .foregroundStyle(destructive ? NanaPalette.warning : NanaPalette.warmWhite)
                Spacer()
                if !destructive {
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                }
            }.frame(minHeight: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct NanaSettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 15)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 13))
    }
}

private enum NanaSettingsAction: String, Identifiable {
    case cache, logout, switchAccount, deleteAccount
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cache: return "Clear cache?"
        case .logout: return "Log out?"
        case .switchAccount: return "Switch accounts?"
        case .deleteAccount: return "Delete account"
        }
    }
    var detail: String {
        switch self {
        case .cache: return "Remove downloaded content caches. Your photos, coins and saved preferences will be kept."
        case .logout, .switchAccount: return "You will return to sign-in. Your saved profile and photos stay with this account."
        case .deleteAccount: return "Account deletion is not available yet. No account data will be removed."
        }
    }
    var actionTitle: String {
        switch self {
        case .cache: return "Clear cache"
        case .logout: return "Confirm exit"
        case .switchAccount: return "Switch accounts"
        case .deleteAccount: return "Got it"
        }
    }
}

struct NanaSettingsView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var showingPrivacy = false
    @State private var showingNotice = false
    @State private var showingAbout = false
    @State private var showingSecurity = false
    @State private var selectedPolicy: AccountPolicyDocument?
    @State private var action: NanaSettingsAction?

    var body: some View {
        NanaProfilePage("Settings") {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "Account security") { showingSecurity = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Add account") { action = .switchAccount }
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "Privacy Settings") { showingPrivacy = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Notice") { showingNotice = true }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Clear cache") { action = .cache }
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "User Agreement") { selectedPolicy = .userAgreement }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Privacy Policy") { selectedPolicy = .privacyPolicy }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "About Us") { showingAbout = true }
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "Delete account", destructive: true) { action = .deleteAccount }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Log out", destructive: true) { action = .logout }
                    }
                }.padding(20)
            }
        }
        .fullScreenCover(isPresented: $showingPrivacy) { NanaPrivacySettingsView() }
        .fullScreenCover(isPresented: $showingNotice) { NanaNoticeSettingsView() }
        .fullScreenCover(isPresented: $showingAbout) { NanaAboutView() }
        .fullScreenCover(isPresented: $showingSecurity) { NanaAccountSecurityView() }
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
        .sheet(item: $action) { selected in
            NanaProfileActionSheet(title: selected.title, detail: selected.detail, actionTitle: selected.actionTitle,
                                   destructive: selected != .deleteAccount) {
                switch selected {
                case .cache: contentStore.clearCache()
                case .logout, .switchAccount: sessionStore.signOut()
                case .deleteAccount: break
                }
            }
        }
        .overlay {
            if let notice = sessionStore.sessionNotice { AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil } }
        }
    }
}

private struct NanaPreferenceRow: View {
    let title: String
    let key: String
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                choice("YES", value: true)
                choice("NO", value: false)
            }
            .padding(3).background(.black.opacity(0.32), in: Capsule())
        }.frame(minHeight: 52)
    }
    private func choice(_ title: String, value: Bool) -> some View {
        let selected = contentStore.preference(key) == value
        return Button { contentStore.setPreference(key, value: value) } label: {
            Text(title).font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? .white : NanaPalette.mutedWhite)
                .frame(width: 44, height: 24)
                .background(selected ? NanaPalette.violet : .clear, in: Capsule())
                .frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(self.title): \(title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NanaPrivacySettingsView: View {
    @State private var selectedPolicy: AccountPolicyDocument?
    var body: some View {
        NanaProfilePage("Privacy Settings") {
            ScrollView {
                VStack(spacing: 14) {
                    NanaSettingsGroup {
                        NanaPreferenceRow(title: "Private information", key: "privateInformation")
                        NanaPreferenceRow(title: "Display status", key: "displayStatus")
                        NanaPreferenceRow(title: "Allow messages", key: "allowMessages")
                        NanaPreferenceRow(title: "Allow video calls", key: "allowVideoCalls")
                    }
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "User Agreement") { selectedPolicy = .userAgreement }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Privacy Policy") { selectedPolicy = .privacyPolicy }
                    }
                }.padding(20)
            }
        }
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
    }
}

private struct NanaNoticeSettingsView: View {
    var body: some View {
        NanaProfilePage("Notice") {
            ScrollView {
                NanaSettingsGroup {
                    NanaPreferenceRow(title: "Allow notifications", key: "allowNotifications")
                    NanaPreferenceRow(title: "Like and follow", key: "likeAndFollow")
                    NanaPreferenceRow(title: "Live broadcast reminder", key: "liveReminder")
                    NanaPreferenceRow(title: "Video call reminder", key: "videoReminder")
                }.padding(20)
            }
        }
    }
}

private struct NanaAboutView: View {
    @State private var selectedPolicy: AccountPolicyDocument?
    @State private var showingHelp = false
    var body: some View {
        NanaProfilePage("About Us") {
            ScrollView {
                VStack(spacing: 22) {
                    Image("NanaBrandIcon").resizable().scaledToFit()
                        .frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 22)
                    Text("Nana · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                    NanaSettingsGroup {
                        NanaSettingsRow(title: "User Agreement") { selectedPolicy = .userAgreement }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Privacy Policy") { selectedPolicy = .privacyPolicy }
                        Divider().overlay(.white.opacity(0.06))
                        NanaSettingsRow(title: "Help Center") { showingHelp = true }
                    }
                }.padding(20)
            }
        }
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
        .fullScreenCover(isPresented: $showingHelp) { NanaHelpCenterView() }
    }
}

private struct NanaHelpCenterView: View {
    var body: some View {
        NanaProfilePage("Help Center") {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    answer("How do I change my photo?", "Open My Profile, tap your avatar, choose a photo and save your profile.")
                    answer("How do I manage unwanted content?", "Use Report or Block from a room, post, conversation or profile. You can manage blocked profiles from My Profile → Blacklist.")
                    answer("Where are my photos?", "Your personal album keeps photos on this device for your account. Open the album from Messages.")
                    answer("How does check-in work?", "Check in once per day to receive 10 activity points. Your history appears in the check-in calendar.")
                }.padding(20)
            }
        }
    }
    private func answer(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 14)).foregroundStyle(NanaPalette.mutedWhite).lineSpacing(4)
        }
    }
}

private struct NanaAccountSecurityView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    var body: some View {
        NanaProfilePage("Account security") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NanaSettingsGroup {
                        HStack {
                            Text("Sign-in method").font(.system(size: 14))
                            Spacer()
                            Text(sessionStore.activeProfile?.signInMethod == "apple" ? "Apple" : "Email")
                                .font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                        }.frame(minHeight: 52)
                    }
                    Text("Keep your sign-in details private. Nana will never ask you to share a password or verification code in a room or chat.")
                        .font(.system(size: 14)).foregroundStyle(NanaPalette.mutedWhite).lineSpacing(4)
                }.padding(20)
            }
        }
    }
}

private struct NanaBlacklistView: View {
    @EnvironmentObject private var contentStore: NanaContentStore
    var body: some View {
        NanaProfilePage("Blacklist") {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if contentStore.hiddenProfiles.isEmpty {
                        NanaEmptyState(title: "Your blacklist is empty", detail: "Blocked profiles will appear here.", actionTitle: nil, action: nil)
                            .padding(.top, 64)
                    }
                    ForEach(contentStore.hiddenProfiles) { profile in
                        NanaRelationshipCard(profile: profile, blocked: true) {
                            contentStore.unhide(profileID: profile.id)
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
    }
}
