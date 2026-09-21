import SwiftUI

enum NanaHarbor: Hashable {
    case home
    case gather
    case inbox
    case me
}

struct NanaHarborShellView: View {
    @Binding var selectedHarbor: NanaHarbor
    @EnvironmentObject private var mockStore: NanaMockStore

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedHarbor {
                case .home: WaterlineWelcomeView()
                case .gather: HarborGatheringView()
                case .inbox: WarmThreadsView()
                case .me: YourShoreView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            NanaTabRail(selectedHarbor: $selectedHarbor)
        }
        .background(NanaPalette.midnight)
        .preferredColorScheme(.dark)
    }
}

private struct NanaTabRail: View {
    @Binding var selectedHarbor: NanaHarbor

    var body: some View {
        HStack(spacing: 0) {
            tab(.home, title: "Live", icon: "play.tv")
            tab(.gather, title: "Rooms", icon: "mic.2")
            tab(.inbox, title: "Messages", icon: "bubble.left.and.bubble.right")
            tab(.me, title: "Me", icon: "person.crop.circle")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial.opacity(0.86))
        .background(NanaPalette.deepSpace.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(NanaPalette.border).frame(height: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func tab(_ destination: NanaHarbor, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedHarbor = destination }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(NanaType.caption.weight(.semibold))
            }
            .foregroundStyle(selectedHarbor == destination ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
            .frame(maxWidth: .infinity, minHeight: 45)
            .background(selectedHarbor == destination ? NanaPalette.violet.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
