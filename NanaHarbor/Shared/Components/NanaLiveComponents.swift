import SwiftUI

struct NanaSectionTitle: View {
    let eyebrow: String
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(NanaType.stamp)
                    .tracking(1.3)
                    .foregroundStyle(NanaPalette.softPink)
                Text(title)
                    .font(NanaType.section)
                    .foregroundStyle(NanaPalette.warmWhite)
            }
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .font(NanaType.caption.weight(.semibold))
                    .foregroundStyle(NanaPalette.electricLilac)
            }
        }
    }
}

struct NanaChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NanaType.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : NanaPalette.mutedWhite)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? NanaPalette.violet : NanaPalette.card, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? NanaPalette.violet : NanaPalette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct NanaRoundAction: View {
    let icon: String
    let title: String
    var tint: Color = NanaPalette.violet
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint, in: Circle())
                Text(title)
                    .font(NanaType.caption.weight(.medium))
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct NanaRoomArtwork: View {
    let room: NanaLiveRoom
    var height: CGFloat = 185

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let asset = room.streamAssetKey {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
            } else {
                LinearGradient(colors: [NanaPalette.neonPink.opacity(0.7), NanaPalette.violet, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: height)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(NanaPalette.neonPink).frame(width: 7, height: 7)
                    Text(room.roomState.uppercased())
                        .font(NanaType.stamp)
                        .tracking(1)
                        .foregroundStyle(.white)
                    Spacer()
                    Label("\(room.viewerCount)", systemImage: "eye")
                        .font(NanaType.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                Text(room.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(room.subtitle)
                    .font(NanaType.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(15)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct NanaPersonRow: View {
    let profile: NanaProfile
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            NanaPlaceholderPortrait(title: profile.displayName, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(NanaType.bodyMedium)
                    .foregroundStyle(NanaPalette.warmWhite)
                Text("\(profile.region) · Lv.\(profile.level)")
                    .font(NanaType.caption)
                    .foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .font(NanaType.caption.weight(.semibold))
                    .foregroundStyle(NanaPalette.electricLilac)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(NanaPalette.cardStrong, in: Capsule())
            }
        }
        .padding(.vertical, 7)
    }
}

struct NanaGlassField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 45)
            .background(NanaPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NanaPalette.border, lineWidth: 1))
    }
}

extension View {
    func nanaGlassField() -> some View { modifier(NanaGlassField()) }
}
