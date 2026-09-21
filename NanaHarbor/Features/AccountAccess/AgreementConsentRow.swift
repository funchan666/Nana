import SwiftUI

struct AgreementConsentRow: View {
    @Binding var isAccepted: Bool
    let openPolicy: (AccountPolicyDocument) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Button { isAccepted.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isAccepted ? AccountEntryAppearance.violet : .clear)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AccountEntryAppearance.linkLilac, lineWidth: 1.5)
                    if isAccepted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Agree to the User Agreement and Privacy Policy")
            .accessibilityValue(isAccepted ? "Agreed" : "Not agreed")

            VStack(alignment: .leading, spacing: 0) {
                Text("I have read and agree to the")
                    .font(.system(size: 12))
                    .foregroundStyle(AccountEntryAppearance.mutedText)
                    .padding(.top, 14)
                HStack(spacing: 4) {
                    policyLink(.userAgreement)
                    Text("and")
                        .font(.system(size: 12))
                        .foregroundStyle(AccountEntryAppearance.mutedText)
                    policyLink(.privacyPolicy)
                }
                Text("Required before continuing")
                    .font(.system(size: 11))
                    .foregroundStyle(AccountEntryAppearance.mutedText)
            }
        }
    }

    private func policyLink(_ document: AccountPolicyDocument) -> some View {
        Button { openPolicy(document) } label: {
            Text(document.title)
                .font(.system(size: 12))
                .underline()
                .foregroundStyle(AccountEntryAppearance.linkLilac)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
