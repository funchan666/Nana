import SwiftUI

struct NanaOnboardingFlow: View {
    let finish: () -> Void
    @State private var pageIndex = 0
    private let pages = [
        OnboardingPage(background: "NanaAccountArtwork", eyebrow: "A SMALLER WAY IN", title: "Notice what is\nclose to you.", detail: "Nana is for the walks, tables, and little rituals that make a place feel familiar.", symbol: "sparkles"),
        OnboardingPage(background: "NanaPlainArtwork", eyebrow: "MAKE ROOM", title: "Choose one\ngood thing.", detail: "Browse nearby moments with a shape and a host, instead of an endless stream.", symbol: "circle.grid.2x2"),
        OnboardingPage(background: "NanaLaunchArtwork", eyebrow: "KEEP THE THREAD", title: "Leave a small\nsignal behind.", detail: "A thoughtful note is enough to turn a passing hello into a circle.", symbol: "waveform.path.ecg"),
    ]

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .bottom) {
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        onboardingPage(page, viewport: viewport.size)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == pageIndex ? AccountEntryAppearance.linkLilac : Color.white.opacity(0.32))
                                .frame(width: index == pageIndex ? 28 : 8, height: 5)
                        }
                    }
                    Button {
                        if pageIndex == pages.count - 1 { finish() } else { withAnimation(.easeInOut(duration: 0.28)) { pageIndex += 1 } }
                    } label: {
                        Text(pageIndex == pages.count - 1 ? "Enter Nana" : "Next")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(AccountEntryAppearance.violet, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 28)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func onboardingPage(_ page: OnboardingPage, viewport: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            AccountArtworkSurface(artworkName: page.background)
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.28), .black.opacity(0.96)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: page.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AccountEntryAppearance.linkLilac)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.16), lineWidth: 1))
                Spacer()
                Text(page.eyebrow)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.66))
                Text(page.title)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(1)
                Text(page.detail)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)
            .padding(.top, 72)
            .padding(.bottom, 180)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingPage {
    let background: String
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
}
