import AuthenticationServices
import Ably
import SwiftUI

@MainActor
struct NanaEntryCoordinator: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionStore = NanaSessionStore()
    @StateObject private var contentStore = NanaContentStore()
    @StateObject private var coinStore = NanaCoinStore()
    @State private var hasPresentedLaunchArtwork = false
    @State private var selectedHarbor: NanaHarbor = .home
    @State private var entryRoute: AccountRoute = .landing
    @StateObject private var webDocument = NanaWebDocument()
    @State private var routeGeneration = UUID()
    @State private var hasConnected = false
    @State private var isSilentRestore = true
    @State private var webFailureMessage: String?
    @State private var receivedEventIDs = Set<String>()
    @State private var realtimeTransport = ConfiguredRealtimeTransport()
    @State private var realtimeScope: String?
    @State private var routeDecision: NanaEntryDecision = .undecided
    @State private var routeTimer: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NanaHarborWebView(document: webDocument)
                .ignoresSafeArea(.all)
                .opacity(routeDecision == .showingB ? 1 : 0)
                .allowsHitTesting(routeDecision == .showingB)
                .accessibilityHidden(routeDecision != .showingB)
            if !hasPresentedLaunchArtwork || (isSilentRestore && routeDecision != .showingA && routeDecision != .showingB) {
                launchLoading
            } else if routeDecision == .showingA && sessionStore.activeProfile != nil {
                NanaHarborShellView(selectedHarbor: $selectedHarbor)
            } else {
                Group {
                    if sessionStore.pendingIdentity != nil || entryRoute == .profile {
                        NanaProfileCompletionView(goBack: { sessionStore.discardPendingIdentity(); entryRoute = .landing })
                    } else {
                        accountRoute
                    }
                }
                .id(sessionStore.entryScreenRevision)
                .opacity(routeDecision == .showingB ? 0 : 1)
                .allowsHitTesting(routeDecision != .showingB && routeDecision != .webFailure)
                .accessibilityHidden(routeDecision == .showingB || routeDecision == .webFailure)
            }
        }
        .ignoresSafeArea(.all)
        .environmentObject(sessionStore)
        .environmentObject(contentStore)
        .environmentObject(coinStore)

        .disabled(sessionStore.accountExitProgress != nil || coinStore.isPresentingPurchase)
        .accessibilityHidden(sessionStore.accountExitProgress != nil || coinStore.isPresentingPurchase)
        .task {
            guard !hasPresentedLaunchArtwork else { return }
            NanaPushTokenCoordinator.shared.start()
            await sessionStore.restoreLocalSession()
            guard !Task.isCancelled else { return }
            if sessionStore.activeProfile != nil { startRealtime() } else { isSilentRestore = false }
            hasPresentedLaunchArtwork = true
        }
        .task(id: sessionStore.activeProfile?.localAccountScope) {
            guard !Task.isCancelled else { return }
            coinStore.beginSession(accountID: sessionStore.activeProfile?.localAccountScope)
            contentStore.beginSession(accountID: sessionStore.activeProfile?.localAccountScope)
            contentStore.setWelcomeFollowersActive(routeDecision == .showingA && scenePhase == .active && sessionStore.accountExitProgress == nil)
            guard sessionStore.activeProfile != nil else {
                try? await NanaCheckInReminder.configure(enabled: false)
                return
            }
            try? await NanaCheckInReminder.configure(enabled: contentStore.preference("dailyCheckInReminder", default: false))
            guard !Task.isCancelled else { return }
            await contentStore.refresh(.bootstrap)
            await contentStore.refresh(.assetManifest)
            guard !Task.isCancelled else { return }
            coinStore.hydrateRemoteBalance(contentStore.payload.wallet.coinBalance)
        }
        .onChange(of: sessionStore.activeProfile?.localAccountScope) { _, scope in
            if scope == nil {
                resetRoute()
                isSilentRestore = false
                entryRoute = sessionStore.signedOutDestination == .login ? .login : .landing
                selectedHarbor = .home
            } else {
                startRealtime()
            }
        }
        .onChange(of: routeDecision) { _, decision in
            contentStore.setWelcomeFollowersActive(decision == .showingA && scenePhase == .active && sessionStore.accountExitProgress == nil)
        }
        .onChange(of: webDocument.phase) { _, phase in
            guard sessionStore.activeProfile != nil else { return }
            switch phase {
            case .ready where routeDecision == .preparingB:
                routeDecision = .showingB
                sessionStore.finishEntryPreparation()
            case .failed(let message) where routeDecision == .preparingB || routeDecision == .showingB:
                showWebFailure(message)
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            contentStore.setWelcomeFollowersActive(routeDecision == .showingA && phase == .active && sessionStore.accountExitProgress == nil)
            guard phase == .active, hasPresentedLaunchArtwork, sessionStore.accountExitProgress == nil else { return }
            Task {
                await sessionStore.validateAppleSession()
                guard sessionStore.activeProfile != nil else { return }
                await contentStore.refresh(.bootstrap)
            }
        }
        .onChange(of: sessionStore.accountExitProgress != nil) { _, exiting in
            contentStore.setWelcomeFollowersActive(routeDecision == .showingA && !exiting && scenePhase == .active)
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            sessionStore.handleAppleCredentialRevocation()
        }
        .overlay {
            if let progress = sessionStore.accountExitProgress {
                NanaAccountExitOverlay(progress: progress)
            } else if coinStore.isPresentingPurchase {
                NanaPaymentOverlay()
            } else if routeDecision == .webFailure, let message = webFailureMessage {
                webFailureActions(message)
            } else if let notice = coinStore.notice {
                AccountConsentNotice(notice: notice) { coinStore.dismissNotice() }
            } else if let notice = sessionStore.sessionNotice {
                AccountConsentNotice(notice: notice) { sessionStore.sessionNotice = nil }
            }
        }
    }

    private func resetRoute() {
        routeGeneration = UUID()
        routeTimer?.cancel()
        routeTimer = nil
        realtimeTransport.onMessage = nil
        realtimeTransport.onState = nil
        realtimeTransport.stop()
        realtimeScope = nil
        hasConnected = false
        receivedEventIDs.removeAll()
        webDocument.stop()
        webFailureMessage = nil
        routeDecision = .undecided
    }

    private func startRealtime() {
        guard let scope = sessionStore.activeProfile?.localAccountScope, realtimeScope != scope else { return }
        resetRoute()
        realtimeScope = scope
        let revision = routeGeneration
        let attempt = sessionStore.entryGeneration
        guard let token = sessionStore.remoteTokenRequest else { commitNativeRoute(); return }
        guard let configuration = try? ConfiguredRealtimeConfiguration(tokenRequest: token, expectedClientID: IntegrationContract.ablyClientID) else {
            connectionFailed()
            return
        }
        routeTimer = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard isCurrent(revision, attempt: attempt), routeDecision == .undecided else { return }
            connectionFailed()
        }
        realtimeTransport.onState = { state in
            Task { @MainActor in
                guard isCurrent(revision, attempt: attempt) else { return }
                switch state {
                case .connected:
                    guard !hasConnected, routeDecision == .undecided else { return }
                    hasConnected = true
                    routeTimer?.cancel()
                    routeTimer = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        guard isCurrent(revision, attempt: attempt), routeDecision == .undecided else { return }
                        commitNativeRoute()
                    }
                case .failed:
                    if routeDecision == .undecided { connectionFailed() }
                default: break
                }
            }
        }
        realtimeTransport.onMessage = { message in
            Task { @MainActor in
                guard isCurrent(revision, attempt: attempt) else { return }
                handleRealtimeMessage(message)
            }
        }
        realtimeTransport.start(configuration: configuration) { callback in
            sessionStore.refreshRealtimeToken(completion: callback)
        }
    }

    private func isCurrent(_ revision: UUID, attempt: UUID) -> Bool {
        routeGeneration == revision && sessionStore.entryGeneration == attempt && sessionStore.activeProfile != nil
            && sessionStore.accountExitProgress == nil
    }

    private func commitNativeRoute() {
        guard routeDecision == .undecided else { return }
        routeTimer?.cancel()
        routeDecision = .showingA
        sessionStore.finishEntryPreparation()
    }

    private func connectionFailed() {
        resetRoute()
        _ = sessionStore.signOut(destination: .welcome)
        sessionStore.sessionNotice = AccountEntryNotice(title: "Nana could not connect", explanation: "Your account session could not start. Please try again.")
    }

    private func showWebFailure(_ message: String) {
        routeTimer?.cancel()
        webFailureMessage = message
        routeDecision = .webFailure
        sessionStore.finishEntryPreparation()
    }

    private func handleRealtimeMessage(_ message: ARTMessage) {
        do {
            let event = try ConfiguredCoreEvent.parse(requestID: UUID(), transportID: message.id, name: message.name, clientID: message.clientId, data: message.data)
            guard receivedEventIDs.insert(event.messageID).inserted else { return }
            switch event.kind {
            case .page:
                guard routeDecision == .undecided else { return }
                switch event.pageDestination {
                case .url(let address):
                    routeTimer?.cancel()
                    routeDecision = .preparingB
                    webDocument.prepare(address)
                case .absent: commitNativeRoute()
                case .invalid: showWebFailure("The account service returned an invalid page address. Please return to welcome and try again.")
                case .notPage: break
                }
            case .expire:
                resetRoute()
                _ = sessionStore.signOut(destination: .welcome)
            case .externalOpen:
                if let address = event.externalURL { UIApplication.shared.open(address, options: [:], completionHandler: nil) }
            case .purchase:
                guard let purchase = event.purchase,
                      let pack = NanaCoinStore.packs.first(where: { $0.productID == purchase.sku }) else { return }
                let revision = routeGeneration
                let attempt = sessionStore.entryGeneration
                Task { @MainActor in
                    guard isCurrent(revision, attempt: attempt) else { return }
                    await coinStore.purchase(pack: pack, orderCode: purchase.reference)
                }
            }
        } catch {
            #if DEBUG
            print("[Realtime] Ignored unsupported event: \(error)")
            #endif
        }
    }

    private func webFailureActions(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Page unavailable").font(.headline)
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            if case .failed = webDocument.phase {
                Button("Retry") {
                    webFailureMessage = nil
                    routeDecision = .preparingB
                    sessionStore.resumeEntryPreparation()
                    webDocument.retry()
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            Button("Return to welcome") {
                resetRoute()
                _ = sessionStore.signOut(destination: .welcome)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 360)
        .background(AccountEntryAppearance.violet)
        .padding(24)
        .accessibilityAddTraits(.isModal)
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

private enum NanaEntryDecision: Equatable { case undecided, preparingB, showingA, showingB, webFailure }

enum AccountRoute: Equatable {
    case landing
    case login
    case registration
    case profile
}

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
