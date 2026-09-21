import AuthenticationServices
import SwiftUI

struct NanaEntryCoordinator: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionStore = NanaSessionStore()
    @StateObject private var contentStore = NanaContentStore()
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
            } else if sessionStore.pendingIdentity != nil {
                NanaProfileCompletionView(goBack: { sessionStore.discardPendingIdentity(); entryRoute = .landing })
            } else {
                accountRoute
            }
        }
        .environmentObject(sessionStore)
        .environmentObject(contentStore)
        .task {
            guard !hasPresentedLaunchArtwork else { return }
            await sessionStore.restoreLocalSession()
            do {
                try await Task.sleep(for: .milliseconds(1500))
                hasPresentedLaunchArtwork = true
            } catch { }
        }
        .task(id: sessionStore.activeProfile?.localAccountScope) {
            contentStore.beginSession(accountID: sessionStore.activeProfile?.localAccountScope)
            guard sessionStore.activeProfile != nil else { return }
            await contentStore.refresh(.bootstrap)
            await contentStore.refresh(.assetManifest)
        }
        .onChange(of: sessionStore.activeProfile?.localAccountScope) { _, scope in
            if scope == nil {
                entryRoute = .landing
                selectedHarbor = .home
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasPresentedLaunchArtwork else { return }
            Task {
                await sessionStore.validateAppleSession()
                guard sessionStore.activeProfile != nil else { return }
                await contentStore.refresh(.bootstrap)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            sessionStore.handleAppleCredentialRevocation()
        }
        .overlay {
            if let notice = sessionStore.sessionNotice {
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
