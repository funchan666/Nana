import SwiftUI

/// An orbital movement below the launch artwork; the image itself already supplies the logo.
struct NanaLaunchProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 2.8
                ZStack {
                    Ellipse()
                        .stroke(AccountEntryAppearance.linkLilac.opacity(0.28), lineWidth: 1.5)
                        .frame(width: 82, height: 28)
                    Ellipse()
                        .trim(from: 0.12, to: 0.42)
                        .stroke(AccountEntryAppearance.linkLilac, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 82, height: 28)
                    Circle()
                        .fill(Color(red: 0.79, green: 1, blue: 0.05))
                        .frame(width: 7, height: 7)
                        .shadow(color: AccountEntryAppearance.linkLilac.opacity(0.6), radius: 8)
                        .offset(x: 41 * cos(phase), y: 14 * sin(phase))
                }
                .rotationEffect(.degrees(-16))
                .frame(width: 110, height: 50)
            }
            .accessibilityHidden(true)
            Text("Opening Nana")
                .font(.system(size: 12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening Nana. Please wait.")
    }
}

/// A separate, quiet rhythm for account submission and web-document loading.
struct AccountLoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            HStack(spacing: 10) {
                ForEach(0..<3) { position in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 5 - Double(position) * 0.85
                    let brightness = reduceMotion ? 0.8 : 0.55 + 0.45 * sin(phase)
                    Capsule()
                        .fill(position == 1 ? Color.white : AccountEntryAppearance.linkLilac)
                        .frame(width: 9, height: 22)
                        .scaleEffect(y: reduceMotion ? 1 : 0.55 + brightness * 0.45)
                        .opacity(brightness)
                }
            }
            .frame(height: 32)
        }
        .accessibilityHidden(true)
    }
}

struct AccountSubmissionProgress: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea()
            VStack(spacing: 16) {
                AccountLoadingDots()
                Text("Please wait…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 30)
            .frame(width: 200)
            .background(Color(red: 0.085, green: 0.045, blue: 0.14), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(AccountEntryAppearance.linkLilac.opacity(0.35), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Please wait. Account request in progress.")
            .accessibilityAddTraits(.isModal)
        }
    }
}
