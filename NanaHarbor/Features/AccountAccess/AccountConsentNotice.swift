import SwiftUI

struct AccountConsentNotice: View {
    let notice: AccountEntryNotice
    let dismissNotice: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissNotice)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(AccountEntryAppearance.linkLilac)
                    .frame(width: 38, height: 4)
                    .accessibilityHidden(true)
                Text(notice.title)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(notice.explanation)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: dismissNotice) {
                    Text("Got it")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AccountEntryAppearance.violet, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(26)
            .frame(maxWidth: 350)
            .background(Color(red: 0.085, green: 0.045, blue: 0.14), in: RoundedRectangle(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .stroke(AccountEntryAppearance.linkLilac.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: AccountEntryAppearance.violet.opacity(0.16), radius: 32, y: 10)
            .padding(24)
            .contentShape(Rectangle())
            .onTapGesture { }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        // Dismissal must remain available even when the presenting form is busy
        // or a parent presentation supplied a disabled environment.
        .environment(\.isEnabled, true)
        .accessibilityAction(.escape, dismissNotice)
    }
}
