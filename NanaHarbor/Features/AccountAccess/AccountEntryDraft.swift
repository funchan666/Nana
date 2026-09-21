import Foundation

/// Credentials exist only while this screen is open; never persist passwords in UserDefaults.
struct AccountEntryDraft {
    var emailAddress = ""
    var accountPassword = ""

    var normalizedEmailAddress: String {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func validationMessage(for purpose: AccountEntryPurpose) -> String? {
        let mailbox = normalizedEmailAddress
        let pieces = mailbox.split(separator: "@", omittingEmptySubsequences: false)
        guard mailbox.count <= 254,
              !mailbox.contains(where: { $0.isWhitespace }),
              pieces.count == 2,
              !pieces[0].isEmpty,
              pieces[0].count <= 64,
              !pieces[0].hasPrefix("."), !pieces[0].hasSuffix("."),
              !pieces[0].contains(".."),
              pieces[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".!#$%&'*+-/=?^_`{|}~".contains($0)) }),
              pieces[1].split(separator: ".", omittingEmptySubsequences: false).count >= 2,
              pieces[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
                  label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
              }) else {
            return "Please enter a valid email address."
        }
        guard !accountPassword.isEmpty else {
            return "Please enter your password."
        }
        if accountPassword.count < 8 || accountPassword.allSatisfy({ $0.isWhitespace }) {
            return "Use at least 8 characters for your password."
        }
        guard accountPassword.count <= 128 else {
            return "Please use a password of 128 characters or fewer."
        }
        return nil
    }
}

enum AccountEntryPurpose: Equatable {
    case signIn
    case createAccount

    var actionArtwork: String {
        self == .signIn ? "NanaLoginAction" : "NanaRegistrationAction"
    }

    var actionLabel: String { self == .signIn ? "Log in" : "Next" }
    var switchingPrompt: String {
        self == .signIn ? "Don't have an account yet?" : "Already have an account?"
    }
    var switchingLabel: String { self == .signIn ? "Sign up" : "Log in" }
}

enum AccountEntryField: Hashable {
    case mailbox
    case password
}

struct AccountEntryNotice: Identifiable {
    let id = UUID()
    let title: String
    let explanation: String
}
