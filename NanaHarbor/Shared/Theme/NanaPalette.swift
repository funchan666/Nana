import SwiftUI

enum NanaPalette {
    static let midnight = Color(red: 0.025, green: 0.018, blue: 0.075)
    static let deepSpace = Color(red: 0.055, green: 0.027, blue: 0.14)
    static let violet = Color(red: 0.48, green: 0.15, blue: 0.98)
    static let electricLilac = Color(red: 0.74, green: 0.48, blue: 1.0)
    static let neonPink = Color(red: 1.0, green: 0.17, blue: 0.72)
    static let softPink = Color(red: 0.98, green: 0.45, blue: 0.78)
    static let warmWhite = Color(red: 0.98, green: 0.96, blue: 1.0)
    static let mutedWhite = Color.white.opacity(0.62)
    static let faintWhite = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.14)
    static let card = Color.white.opacity(0.075)
    static let cardStrong = Color.white.opacity(0.11)
    static let warning = Color(red: 1.0, green: 0.37, blue: 0.44)

    // Kept for shared entry components that were built before the A-side redesign.
    static let fog = midnight
    static let paper = deepSpace
    static let spruce = warmWhite
    static let quietSlate = mutedWhite
    static let mist = Color.white.opacity(0.18)
    static let terracotta = neonPink
    static let terracottaWash = Color.white.opacity(0.1)
    static let line = border

    static let screenPadding: CGFloat = 18
    static let cardRadius: CGFloat = 18
}

enum NanaType {
    static let hero = Font.system(size: 30, weight: .semibold, design: .rounded)
    static let section = Font.system(size: 21, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular, design: .rounded)
    static let bodyMedium = Font.system(size: 15, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    static let stamp = Font.system(size: 10, weight: .semibold, design: .monospaced)
}

struct NanaCardSurface: ViewModifier {
    var fill: Color = NanaPalette.card
    var border: Color = NanaPalette.border

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: NanaPalette.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NanaPalette.cardRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
    }
}

extension View {
    func nanaCard(fill: Color = NanaPalette.card, border: Color = NanaPalette.border) -> some View {
        modifier(NanaCardSurface(fill: fill, border: border))
    }
}

struct NanaBackdrop: View {
    var imageName: String? = nil
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [NanaPalette.deepSpace, NanaPalette.midnight], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let imageName {
                NanaMediaPreview(assetKey: imageName)
                    .opacity(0.42)
                    .clipped()
            }
            RadialGradient(colors: [NanaPalette.violet.opacity(0.2), .clear], center: .topTrailing, startRadius: 12, endRadius: 420)
            if dimmed { Color.black.opacity(0.22) }
        }
        .ignoresSafeArea()
    }
}

struct NanaPlaceholderPortrait: View {
    let title: String
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            LinearGradient(colors: [NanaPalette.neonPink.opacity(0.9), NanaPalette.violet, Color.blue.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(title.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined())
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
    }
}

struct NanaPrimaryButtonStyle: ButtonStyle {
    var tint: Color = NanaPalette.violet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(tint.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
            .shadow(color: tint.opacity(0.36), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
