import SwiftUI
import UIKit

/// Presentation data for a future ranking response. No ranks are inferred from
/// follower counts, room attendance, or the wallet's unrelated contribution total.
enum NanaRankingCategory: String, CaseIterable, Identifiable {
    case popularity = "Popularity"
    case liveRoom = "Live room"
    case voiceRoom = "Voice room"
    var id: String { rawValue }
}

struct NanaRankingEntry: Identifiable {
    let id: String
    let profileID: String
    let category: NanaRankingCategory
    let rank: Int
    let displayName: String
    let avatarAssetKey: String?
    let level: Int
    let giftCount: Int
    var isCurrentUser = false
}

struct NanaRankingView: View {
    // The current read contract has no ranking endpoint. Its adapter can supply
    // entries here when confirmed, without replacing the screen with a placeholder.
    var entries: [NanaRankingEntry] = []
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var category: NanaRankingCategory = .popularity
    @State private var showingRules = false
    @State private var selectedProfile: NanaProfile?

    private var visibleEntries: [NanaRankingEntry] {
        entries.filter {
            $0.category == category && $0.rank > 0 && !contentStore.blockedProfileIDs.contains($0.profileID)
        }.sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank }
    }
    private var personalEntry: NanaRankingEntry? {
        visibleEntries.first(where: \.isCurrentUser)
    }

    var body: some View {
        ZStack {
            NanaTabBackdrop()
            VStack(spacing: 0) {
                navigationBar
                rankingHeader
                rankingTable
            }
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedProfile) { NanaUserProfileView(profile: $0) }
        .alert("About rankings", isPresented: $showingRules) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text("Switch between Popularity, Live room and Voice room to view published gift rankings. A dash means your rank or gift total is not available. Rankings will appear when the ranking service is available.")
        }
    }

    private var navigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left.circle")
                    .font(.system(size: 21, weight: .light)).frame(width: 44, height: 44)
            }.accessibilityLabel("Back")
            Spacer()
            Button { showingRules = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 21, weight: .light)).frame(width: 44, height: 44)
            }.accessibilityLabel("About rankings")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var rankingHeader: some View {
        ZStack(alignment: .bottomTrailing) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_008", contentMode: .fit)
                .frame(width: 210, height: 158)
                .offset(x: 18, y: 6)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                Text("Ranking List")
                    .font(.system(size: 21, weight: .heavy).italic())
                Text("View recent rankings")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 12)
                categoryPicker
                    .frame(maxWidth: 270)
                    .padding(.bottom, 22)
            }
            .padding(.top, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 145)
        .clipped()
    }

    private var categoryPicker: some View {
        HStack(spacing: 0) {
            ForEach(NanaRankingCategory.allCases) { item in
                Button { category = item } label: {
                    Text(item.rawValue)
                        .font(.system(size: 10, weight: category == item ? .semibold : .regular))
                        .foregroundStyle(category == item ? .white : .white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(category == item ? NanaPalette.violet : .clear, in: Capsule())
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == item ? [.isSelected] : [])
            }
        }
        .background {
            Capsule().fill(.white.opacity(0.15)).frame(height: 28)
        }
    }

    private var rankingTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Ranking").frame(width: 48)
                Text("Nickname").frame(maxWidth: .infinity, alignment: .leading)
                Text("Number of gifts").frame(width: 96, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(.black.opacity(0.28), in: Capsule())
            .padding(.top, 12)
            .padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if visibleEntries.isEmpty {
                        VStack(spacing: 7) {
                            Text("No rankings yet").font(.system(size: 15, weight: .semibold))
                            Text("Published rankings will appear here.")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 38)
                    } else {
                        ForEach(visibleEntries) { entry in
                            Button {
                                selectedProfile = contentStore.profile(with: entry.profileID)
                            } label: { rankingRow(entry) }
                            .buttonStyle(.plain)
                            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .id(category)

            personalRanking
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(LinearGradient(colors: [Color(red: 0.32, green: 0.21, blue: 0.27).opacity(0.91), Color(red: 0.16, green: 0.13, blue: 0.075)], startPoint: .top, endPoint: .center))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func rankingRow(_ entry: NanaRankingEntry) -> some View {
        HStack(spacing: 10) {
            rankBadge(entry.rank).frame(width: 48)
            NanaAvatarView(title: entry.displayName, assetKey: entry.avatarAssetKey, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                levelBadge(entry.level)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_009", contentMode: .fit)
                    .frame(width: 16, height: 20).accessibilityHidden(true)
                Text(entry.giftCount.formatted(.number.notation(.compactName)))
                    .font(.system(size: 11)).monospacedDigit()
            }.frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 59)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func rankBadge(_ rank: Int) -> some View {
        if (1...3).contains(rank) {
            let asset = rank == 1 ? "005" : rank == 2 ? "001" : "003"
            NanaAssetImage(assetKey: "nana.voice.voice_asset_\(asset)", contentMode: .fit)
                .frame(width: 29, height: 37)
                .accessibilityLabel("Rank \(rank)")
        } else {
            Text(String(rank)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func levelBadge(_ level: Int) -> some View {
        Text("Lv.\(level)")
            .font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(LinearGradient(colors: [.orange, NanaPalette.neonPink, NanaPalette.violet, .cyan], startPoint: .leading, endPoint: .trailing), in: Capsule())
    }

    private var personalRanking: some View {
        HStack(spacing: 10) {
            Group {
                if let entry = personalEntry { rankBadge(entry.rank) }
                else { Text("—").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)) }
            }.frame(width: 48)
            Group {
                if let data = sessionStore.activeProfile?.avatarData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(Circle())
                } else {
                    NanaAvatarView(title: sessionStore.activeProfile?.displayName ?? "You", assetKey: personalEntry?.avatarAssetKey, size: 34)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sessionStore.activeProfile?.displayName ?? "You").font(.system(size: 12)).lineLimit(1)
                levelBadge(personalEntry?.level ?? contentStore.payload.wallet.level)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(personalEntry.map { $0.giftCount.formatted(.number.notation(.compactName)) } ?? "—")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 64)
        .background(Color(red: 0.15, green: 0.13, blue: 0.23), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.28), lineWidth: 0.6))
        .accessibilityElement(children: .combine)
    }
}

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
                NanaMediaPreview(assetKey: asset)
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
            NanaAvatarView(title: profile.displayName, assetKey: profile.avatarAssetKey, size: 48)
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
