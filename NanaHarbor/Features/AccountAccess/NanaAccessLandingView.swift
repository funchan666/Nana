import AuthenticationServices
import SwiftUI

struct NanaAccessLandingView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var hasAcceptedAgreements = false
    @State private var selectedPolicy: AccountPolicyDocument?
    @State private var entryNotice: AccountEntryNotice?
    @State private var isAppleLoading = false
    @State private var isVisitorLoading = false
    @State private var appleService = AppleSignInService()
    @State private var methodsLoading = true

    let openLogin: () -> Void
    let openRegistration: () -> Void
    let openProfile: () -> Void

    var body: some View {
        ZStack {
            AccountArtworkSurface(artworkName: "NanaAccountArtwork")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)

            GeometryReader { viewport in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(320, viewport.size.height * 0.54))
                        VStack(spacing: 0) {
                            if methodsLoading {
                                AccountLoadingDots()
                                    .frame(maxWidth: .infinity, minHeight: 96)
                            } else {
                                if sessionStore.loginMethods.email {
                                    AccountArtworkButton(artworkName: "NanaLoginAction", spokenTitle: "Log in with email", action: { openLogin() })
                                        .padding(.horizontal, 17)
                                }
                                if sessionStore.loginMethods.register {
                                    Button { openRegistration() } label: {
                                        HStack(spacing: 5) {
                                            Text("New to Nana?").foregroundStyle(AccountEntryAppearance.mutedText)
                                            Text("Create an account").underline().foregroundStyle(AccountEntryAppearance.linkLilac)
                                        }
                                        .font(.system(size: 12)).frame(minHeight: 48)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if sessionStore.loginMethods.visitor {
                                    Button(action: beginVisitorSignIn) {
                                        Text("Continue as guest")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity, minHeight: 48)
                                            .background(AccountEntryAppearance.violet.opacity(0.86), in: Capsule())
                                            .overlay {
                                                Capsule().stroke(AccountEntryAppearance.linkLilac.opacity(0.8), lineWidth: 1)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 17)
                                    .padding(.top, 2)
                                }
                            }
                            HStack(spacing: 5) {
                                Rectangle().frame(width: 24, height: 0.5)
                                Text("or continue with Apple")
                                    .font(.system(size: 12))
                                Rectangle().frame(width: 24, height: 0.5)
                            }
                            .foregroundStyle(AccountEntryAppearance.mutedText)
                            .padding(.vertical, 18)
                            if sessionStore.loginMethods.apple {
                                AccountArtworkButton(artworkName: "NanaAppleAction", spokenTitle: "Sign in with Apple", action: beginAppleSignIn)
                                    .padding(.horizontal, 17)
                            }
                            AgreementConsentRow(isAccepted: $hasAcceptedAgreements) { selectedPolicy = $0 }
                                .padding(.top, 20)
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 32)
                    }
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .ignoresSafeArea(.all)
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark).modifier(NanaPrivacyShield()) }
        .disabled(entryNotice != nil || isAppleLoading || isVisitorLoading || methodsLoading)
        .task {
            await sessionStore.loadLoginMethods()
            methodsLoading = false
        }
        .overlay {
            if let entryNotice {
                AccountConsentNotice(notice: entryNotice) { self.entryNotice = nil }
            } else if isAppleLoading || isVisitorLoading {
                AccountSubmissionProgress()
            }
        }
    }

    private func requireAgreementConsent() -> Bool {
        guard hasAcceptedAgreements else {
            entryNotice = AccountEntryNotice(
                title: "Your agreement comes first",
                explanation: "Please review both agreements and tick the box before continuing."
            )
            return false
        }
        return true
    }

    private func beginAppleSignIn() {
        guard requireAgreementConsent() else { return }
        isAppleLoading = true
        appleService.begin { result in
            Task { @MainActor in
                switch result {
                case .success(let identity):
                    do {
                        let hasCompletedProfile = try await sessionStore.acceptAppleAuthorization(identity)
                        isAppleLoading = false
                        if !hasCompletedProfile { openProfile() }
                    } catch {
                        isAppleLoading = false
                        entryNotice = AccountEntryNotice(title: "Apple sign-in didn't finish", explanation: error.localizedDescription)
                    }
                case .failure(let error):
                    isAppleLoading = false
                    if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled { return }
                    entryNotice = AccountEntryNotice(title: "Apple sign-in didn't finish", explanation: "Please try Sign in with Apple again.")
                }
            }
        }
    }

    private func beginVisitorSignIn() {
        guard requireAgreementConsent() else { return }
        isVisitorLoading = true
        Task { @MainActor in
            do {
                try await sessionStore.signInAsVisitor()
                isVisitorLoading = false
            } catch {
                isVisitorLoading = false
                entryNotice = AccountEntryNotice(title: "Guest access didn't finish", explanation: error.localizedDescription)
            }
        }
    }
}
