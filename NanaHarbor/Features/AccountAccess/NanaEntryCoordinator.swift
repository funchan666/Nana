import SwiftUI

struct NanaEntryCoordinator: View {
    @StateObject private var sessionStore = NanaSessionStore()
    @StateObject private var mockStore = NanaMockStore()
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
                    .environmentObject(mockStore)
            } else if !sessionStore.onboardingFinished {
                NanaOnboardingFlow { sessionStore.finishOnboarding() }
            } else if sessionStore.pendingIdentity != nil {
                NanaProfileCompletionView(goBack: { sessionStore.discardPendingIdentity(); entryRoute = .landing })
            } else {
                accountRoute
            }
        }
        .environmentObject(sessionStore)
        .environmentObject(mockStore)
        .task {
            guard !hasPresentedLaunchArtwork else { return }
            do {
                try await Task.sleep(for: .milliseconds(1500))
                hasPresentedLaunchArtwork = true
            } catch { }
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
