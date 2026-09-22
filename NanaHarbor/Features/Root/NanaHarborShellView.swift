import SwiftUI

enum NanaHarbor: Hashable {
    case home
    case gather
    case inbox
    case me
}

struct NanaHarborShellView: View {
    @Binding var selectedHarbor: NanaHarbor
    @EnvironmentObject private var contentStore: NanaContentStore

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
        .background(NanaPalette.tabBarBackground)
        .preferredColorScheme(.dark)
        // The notice intercepts background taps itself. Disabling this presenter
        // also disables notices inside its full-screen rooms and nested sheets.
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }
}

private struct NanaTabRail: View {
    @Binding var selectedHarbor: NanaHarbor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            tab(.home, title: "Live")
            tab(.gather, title: "Voice")
            tab(.inbox, title: "Message")
            tab(.me, title: "Me")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(NanaPalette.tabBarBackground.ignoresSafeArea(edges: .bottom))
    }

    private func tab(_ destination: NanaHarbor, title: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selectedHarbor = destination
            }
        } label: {
            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: selectedHarbor == destination ? .medium : .regular))
                    .foregroundStyle(selectedHarbor == destination ? Color.white : Color.white.opacity(0.45))
                    .lineLimit(1)
                Capsule()
                    .fill(selectedHarbor == destination ? NanaPalette.violet : Color.clear)
                    .frame(width: 20, height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedHarbor == destination ? .isSelected : [])
    }
}
