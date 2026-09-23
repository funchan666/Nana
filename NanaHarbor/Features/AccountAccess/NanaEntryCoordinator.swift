import AuthenticationServices
import SwiftUI

struct NanaEntryCoordinator: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionStore = NanaSessionStore()
    @StateObject private var contentStore = NanaContentStore()
    @StateObject private var coinStore = NanaCoinStore()
    @State private var hasPresentedLaunchArtwork = false
    @State private var selectedHarbor: NanaHarbor = .home
    @State private var entryRoute: AccountRoute = .landing

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !hasPresentedLaunchArtwork {
                launchLoading
            } else if sessionStore.activeProfile != nil {
                NanaHarborShellView(selectedHarbor: $selectedHarbor)
                    .environmentObject(sessionStore)
                    .environmentObject(contentStore)
                    .environmentObject(coinStore)
            } else if sessionStore.pendingIdentity != nil {
                NanaProfileCompletionView(goBack: { sessionStore.discardPendingIdentity(); entryRoute = .landing })
            } else {
                accountRoute
            }
        }
        .environmentObject(sessionStore)
        .environmentObject(contentStore)
        .environmentObject(coinStore)
        .disabled(sessionStore.accountExitProgress != nil)
        .accessibilityHidden(sessionStore.accountExitProgress != nil)
        .task {
            guard !hasPresentedLaunchArtwork else { return }
            await sessionStore.restoreLocalSession()
            do {
                try await Task.sleep(for: .milliseconds(1500))
                hasPresentedLaunchArtwork = true
            } catch { }
        }
        .task(id: sessionStore.activeProfile?.localAccountScope) {
            try? await NanaCheckInReminder.configure(enabled: false)
            coinStore.beginSession(accountID: sessionStore.activeProfile?.localAccountScope)
            contentStore.beginSession(accountID: sessionStore.activeProfile?.localAccountScope)
            contentStore.setWelcomeFollowersActive(scenePhase == .active && sessionStore.accountExitProgress == nil)
            guard sessionStore.activeProfile != nil else { return }
            try? await NanaCheckInReminder.configure(enabled: contentStore.preference("dailyCheckInReminder", default: false))
            guard !Task.isCancelled else { return }
            await contentStore.refresh(.bootstrap)
            await contentStore.refresh(.assetManifest)
            guard !Task.isCancelled else { return }
            coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
        }
        .onChange(of: sessionStore.activeProfile?.localAccountScope) { _, scope in
            if scope == nil {
                entryRoute = sessionStore.signedOutDestination == .login ? .login : .landing
                selectedHarbor = .home
            }
        }
        .onChange(of: scenePhase) { _, phase in
            contentStore.setWelcomeFollowersActive(phase == .active && sessionStore.accountExitProgress == nil)
            guard phase == .active, hasPresentedLaunchArtwork, sessionStore.accountExitProgress == nil else { return }
            Task {
                await sessionStore.validateAppleSession()
                guard sessionStore.activeProfile != nil else { return }
                await contentStore.refresh(.bootstrap)
            }
        }
        .onChange(of: sessionStore.accountExitProgress != nil) { _, exiting in
            contentStore.setWelcomeFollowersActive(!exiting && scenePhase == .active)
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            sessionStore.handleAppleCredentialRevocation()
        }
        .overlay {
            if let progress = sessionStore.accountExitProgress {
                NanaAccountExitOverlay(progress: progress)
            } else if let gift = coinStore.welcomeGift {
                NanaWelcomeGiftOverlay(gift: gift) { coinStore.dismissWelcomeGift() }
            } else if let notice = coinStore.notice {
                AccountConsentNotice(notice: notice) { coinStore.dismissNotice() }
            } else if let notice = sessionStore.sessionNotice {
                AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil }
            }
        }
    }

    private var launchLoading: some View {
        ZStack {
            AccountArtworkSurface(artworkName: "NanaLaunchArtwork")
            GeometryReader { display in
                NanaLaunchProgress()
                    .position(x: display.size.width / 2, y: display.size.height * 0.68)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var accountRoute: some View {
        switch entryRoute {
        case .landing:
            NanaAccessLandingView(openLogin: { entryRoute = .login }, openRegistration: { entryRoute = .registration }, openProfile: { entryRoute = .profile })
        case .login:
            NanaCredentialAccessView(mode: .login, goBack: { entryRoute = .landing }, openRegistration: { entryRoute = .registration }, openProfile: { entryRoute = .profile })
        case .registration:
            NanaCredentialAccessView(mode: .registration, goBack: { entryRoute = .landing }, openRegistration: nil, openProfile: { entryRoute = .profile })
        case .profile:
            NanaProfileCompletionView(goBack: { sessionStore.discardPendingIdentity(); entryRoute = .landing })
        }
    }
}

enum AccountRoute {
    case landing
    case login
    case registration
    case profile
}

/// Reuses Nana's original artwork; no system alert or decorative system icon.
struct NanaAccountExitOverlay: View {
    let progress: NanaAccountExitProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Image("NanaSettingsSecurity").resizable().scaledToFit().frame(width: 132, height: 100)
                    .opacity(progress.isWorking && !glowing ? 0.45 : 1)
                    .animation(progress.isWorking && !reduceMotion ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil, value: glowing)
                    .accessibilityHidden(true)
                Text(progress.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                Text(progress.detail).font(.subheadline).foregroundStyle(NanaPalette.mutedWhite).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white).padding(28).frame(maxWidth: 330)
            .background {
                Image("NanaSettingsCardSurface").resizable(capInsets: EdgeInsets(top: 54, leading: 54, bottom: 54, trailing: 54))
            }
            .padding(20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .onAppear { glowing = true }
        .onChange(of: progress.isWorking) { _, working in glowing = !working }
    }
}
