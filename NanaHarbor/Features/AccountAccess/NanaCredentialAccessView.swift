import SwiftUI

struct NanaCredentialAccessView: View {
    enum Mode: Equatable {
        case login
        case registration

        var title: String { self == .login ? "Welcome back." : "Create your account." }
        var eyebrow: String { self == .login ? "ACCOUNT LOGIN" : "NEW ACCOUNT" }
        var buttonTitle: String { self == .login ? "Start" : "Sign up" }
        var prompt: String { self == .login ? "Don't have an account yet?" : "Already have an account?" }
        var promptAction: String { self == .login ? "Sign up" : "Log in" }
    }

    @EnvironmentObject private var sessionStore: NanaSessionStore
    let mode: Mode
    let goBack: () -> Void
    let openRegistration: (() -> Void)?
    let openProfile: () -> Void

    @State private var emailAddress = ""
    @State private var password = ""
    @State private var hasAcceptedAgreements = false
    @State private var validationMessage: String?
    @State private var entryNotice: AccountEntryNotice?
    @State private var selectedPolicy: AccountPolicyDocument?
    @State private var isSubmitting = false
    @State private var submissionTask: Task<Void, Never>?
    @State private var showPassword = false
    @FocusState private var focusedField: CredentialField?

    enum CredentialField { case email, password }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { scrollReader in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode.eyebrow)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(AccountEntryAppearance.mutedText)
                            Text(mode.title)
                                .font(.system(size: 31, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 32)
                        fields
                            .id("credential-fields")
                        AgreementConsentRow(isAccepted: $hasAcceptedAgreements) { selectedPolicy = $0 }
                            .padding(.top, 22)
                        Button(action: submit) {
                            Text(mode.buttonTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(AccountEntryAppearance.violet, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                        HStack(spacing: 5) {
                            Text(mode.prompt).foregroundStyle(AccountEntryAppearance.mutedText)
                            Button(mode.promptAction) {
                                if mode == .login { openRegistration?() } else { goBack() }
                            }
                            .underline()
                            .foregroundStyle(AccountEntryAppearance.linkLilac)
                        }
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 30)
                    .frame(minHeight: viewport.size.height + 1)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, focus in
                    if focus != nil {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollReader.scrollTo("credential-fields", anchor: .top)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea(.container)
        .overlay(alignment: .topLeading) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AccountEntryAppearance.linkLilac)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
            .padding(.top, 46)
            .accessibilityLabel("Back")
        }
        .background { AccountArtworkSurface(artworkName: "NanaAccountArtwork") }
        .background(.black)
        .onAppear {
            if mode == .login, emailAddress.isEmpty { emailAddress = sessionStore.suggestedSignInEmail }
        }
        .fullScreenCover(item: $selectedPolicy) { AccountPolicyBrowser(document: $0).preferredColorScheme(.dark) }
        .disabled(entryNotice != nil || isSubmitting)
        .overlay {
            if let entryNotice {
                AccountConsentNotice(notice: entryNotice) { self.entryNotice = nil }
            } else if isSubmitting {
                AccountSubmissionProgress()
            }
        }
        .onDisappear {
            submissionTask?.cancel()
            submissionTask = nil
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 24) {
            accountField(title: "Email", placeholder: "Your email", value: $emailAddress, field: .email, keyboard: .emailAddress, contentType: .username)
            HStack(alignment: .bottom, spacing: 0) {
                accountField(title: "Password", placeholder: "Your password", value: $password, field: .password, keyboard: nil, contentType: mode == .registration ? .newPassword : .password, secure: !showPassword)
                Button {
                    showPassword.toggle()
                    focusedField = .password
                } label: {
                    Image(showPassword ? "NanaPasswordVisible" : "NanaPasswordHidden")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func accountField(title: String, placeholder: String, value: Binding<String>, field: CredentialField, keyboard: UIKeyboardType?, contentType: UITextContentType, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(AccountEntryAppearance.mutedText)
            Group {
                if secure {
                    SecureField(placeholder, text: value)
                } else {
                    TextField(placeholder, text: value)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(AccountEntryAppearance.linkLilac)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(contentType)
            .focused($focusedField, equals: field)
            .onSubmit { if field == .email { focusedField = .password } else { submit() } }
            .modifier(KeyboardTypeModifier(type: keyboard))
            Rectangle().fill(AccountEntryAppearance.fieldRule).frame(height: 0.5)
        }
    }

    private func submit() {
        focusedField = nil
        guard hasAcceptedAgreements else {
            entryNotice = AccountEntryNotice(title: "Your agreement comes first", explanation: "Please review both agreements and tick the box before continuing.")
            return
        }
        let draft = AccountEntryDraft(emailAddress: emailAddress, accountPassword: password)
        validationMessage = draft.validationMessage(for: mode == .login ? .signIn : .createAccount)
        guard validationMessage == nil else { return }
        isSubmitting = true
        let email = draft.normalizedEmailAddress
        let secret = password
        submissionTask = Task { @MainActor in
            defer { isSubmitting = false; submissionTask = nil }
            do {
                try await Task.sleep(for: .seconds(3.4))
                try Task.checkCancellation()
                if mode == .login {
                    try sessionStore.signIn(emailAddress: email, password: secret)
                } else {
                    try sessionStore.preparePasswordRegistration(emailAddress: email, password: secret)
                    openProfile()
                }
                password = ""
            } catch is CancellationError {
                return
            } catch {
                entryNotice = AccountEntryNotice(title: "Couldn't finish", explanation: error.localizedDescription)
            }
        }
    }
}

private struct KeyboardTypeModifier: ViewModifier {
    let type: UIKeyboardType?
    func body(content: Content) -> some View {
        content.keyboardType(type ?? .default)
    }
}
