import SwiftUI

/// Measures the full display before filling, so portrait artwork never introduces letterboxing.
struct AccountArtworkSurface: View {
    let artworkName: String

    var body: some View {
        GeometryReader { canvas in
            Image(artworkName)
                .resizable()
                .scaledToFill()
                .frame(width: canvas.size.width, height: canvas.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

enum AccountEntryAppearance {
    static let violet = Color(red: 0.49, green: 0.16, blue: 1)
    static let linkLilac = Color(red: 0.74, green: 0.52, blue: 1)
    static let mutedText = Color.white.opacity(0.62)
    static let fieldRule = Color.white.opacity(0.28)
}

struct AccountArtworkButton: View {
    let artworkName: String
    let spokenTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(artworkName)
                .resizable()
                .scaledToFit()
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(AccountPressStyle())
        .accessibilityLabel(spokenTitle)
    }
}

private struct AccountPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}
