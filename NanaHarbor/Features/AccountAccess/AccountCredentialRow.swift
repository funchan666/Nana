import SwiftUI

struct AccountCredentialRow: View {
    let credentialField: AccountEntryField
    let entryPurpose: AccountEntryPurpose
    @Binding var enteredValue: String
    let keyboardFocus: FocusState<AccountEntryField?>.Binding
    let submitEntry: () -> Void
    @State private var revealsPassword = false

    private var isPassword: Bool { credentialField == .password }
    private var fieldTitle: String { isPassword ? "Password" : "Email" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fieldTitle)
                .font(.system(size: 12))
                .foregroundStyle(AccountEntryAppearance.mutedText)

            HStack(spacing: 0) {
                editableValue
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .tint(AccountEntryAppearance.linkLilac)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused(keyboardFocus, equals: credentialField)
                    .submitLabel(isPassword ? .go : .next)
                    .onSubmit {
                        if isPassword { submitEntry() } else { keyboardFocus.wrappedValue = .password }
                    }
                    .accessibilityLabel(fieldTitle)
                    .padding(.leading, 12)

                if isPassword {
                    Button {
                        revealsPassword.toggle()
                        keyboardFocus.wrappedValue = .password
                    } label: {
                        Image(revealsPassword ? "NanaPasswordVisible" : "NanaPasswordHidden")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                } else if !enteredValue.isEmpty {
                    Button {
                        enteredValue = ""
                        keyboardFocus.wrappedValue = .mailbox
                    } label: {
                        Image("NanaClearEntry")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear email address")
                }
            }
            .frame(minHeight: 44)
            .buttonStyle(.plain)

            Rectangle()
                .fill(AccountEntryAppearance.fieldRule)
                .frame(height: 0.5)
        }
        .onChange(of: entryPurpose) { _, _ in revealsPassword = false }
    }

    @ViewBuilder private var editableValue: some View {
        if isPassword {
            Group {
                if revealsPassword {
                    TextField("", text: $enteredValue, prompt: Text("Your password").foregroundStyle(AccountEntryAppearance.mutedText))
                } else {
                    SecureField("", text: $enteredValue, prompt: Text("Your password").foregroundStyle(AccountEntryAppearance.mutedText))
                }
            }
            .textContentType(entryPurpose == .createAccount ? .newPassword : .password)
        } else {
            TextField("", text: $enteredValue, prompt: Text("Your email").foregroundStyle(AccountEntryAppearance.mutedText))
                .keyboardType(.emailAddress)
                .textContentType(.username)
        }
    }
}
