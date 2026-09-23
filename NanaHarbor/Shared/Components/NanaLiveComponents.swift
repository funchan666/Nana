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

/// Local presentation fixtures, kept separate from published rankings and wallet data.
enum NanaRankingSamples {
    private struct Member {
        let id: String
        let name: String
        let photo: String
        let level: Int
    }

    private static let members: [Member] = [
        Member(id: "profile-ava", name: "Ava Monroe", photo: "Dc0SA4UiUy3", level: 28),
        Member(id: "profile-jules", name: "Jules Harper", photo: "Dc0XoT9DgeO", level: 25),
        Member(id: "profile-mira", name: "Mira Laurent", photo: "Dc1CvDfCCHN", level: 24),
        Member(id: "profile-noah", name: "Noah Reed", photo: "Dc1Ii5HACCq", level: 34),
        Member(id: "profile-lin", name: "Lin Wei", photo: "Dc1UKGTDL1J", level: 21),
        Member(id: "ranking-sample-ruby", name: "Ruby Ellis", photo: "Dc6OjcqAodc", level: 23),
        Member(id: "ranking-sample-theo", name: "Theo Brooks", photo: "DdJ2uSSDENz", level: 19),
        Member(id: "ranking-sample-iris", name: "Iris Bennett", photo: "DczCXb6HMNj", level: 22),
        Member(id: "ranking-sample-finn", name: "Finn Hayes", photo: "DdTY1ZoDJ_o", level: 18),
        Member(id: "ranking-sample-skye", name: "Skye Morgan", photo: "DdMJA6mE7N0", level: 20)
    ]

    static func entries(for category: NanaRankingCategory) -> [NanaRankingEntry] {
        let order: [Int]
        let gifts: [Int]
        switch category {
        case .popularity:
            order = [0, 3, 2, 1, 5, 4, 7, 6, 9, 8]
            gifts = [258420, 231860, 208740, 186320, 164580, 142910, 121460, 98620, 84350, 72180]
        case .liveRoom:
            order = [3, 1, 5, 0, 8, 2, 6, 9, 4, 7]
            gifts = [196850, 175420, 158760, 134910, 118340, 97480, 85260, 71630, 58420, 46380]
        case .voiceRoom:
            order = [4, 2, 7, 9, 0, 6, 1, 5, 3, 8]
            gifts = [168920, 149680, 128430, 112750, 96780, 82340, 69850, 56410, 43280, 31860]
        }
        return order.enumerated().map { position, index in
            let member = members[index]
            return NanaRankingEntry(
                id: "sample-\(category.rawValue)-\(member.id)", profileID: member.id,
                category: category, rank: position + 1, displayName: member.name,
                avatarAssetKey: "nana.pic.\(member.photo)", level: member.level, giftCount: gifts[position]
            )
        }
    }
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

    private var publishedCategoryEntries: [NanaRankingEntry] {
        entries.filter { $0.category == category && $0.rank > 0 }
    }
    private var showsSampleRankings: Bool { publishedCategoryEntries.isEmpty }
    private var visibleEntries: [NanaRankingEntry] {
        let categoryEntries = showsSampleRankings ? NanaRankingSamples.entries(for: category) : publishedCategoryEntries
        return categoryEntries.filter { !contentStore.hiddenAuthorIDs.contains($0.profileID) }
            .sorted { $0.rank == $1.rank ? $0.id < $1.id : $0.rank < $1.rank }
    }
    private var personalEntry: NanaRankingEntry? {
        guard !showsSampleRankings else { return nil }
        return visibleEntries.first(where: \.isCurrentUser)
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
        .sheet(isPresented: $showingRules) {
            NanaRankingGuideView(category: category, showsSampleRankings: showsSampleRankings)
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
                Text(showsSampleRankings ? "Sample rankings" : "View recent rankings")
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
                            if !showsSampleRankings, let profile = contentStore.profile(with: entry.profileID) {
                                Button { selectedProfile = profile } label: { rankingRow(entry) }
                                    .buttonStyle(.plain)
                            } else {
                                rankingRow(entry)
                            }
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

private struct NanaRankingGuideView: View {
    let category: NanaRankingCategory
    let showsSampleRankings: Bool
    @Environment(\.dismiss) private var dismiss

    private let surface = Color(red: 0.075, green: 0.055, blue: 0.105)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    categories
                    explanation(number: "02", title: "Reading the list",
                                detail: "Rank 1 is the highest position. The gift total is shown on the right; K means thousand. Hidden profiles are removed without changing the remaining ranks.")
                    explanation(number: "03", title: "Your place",
                                detail: "The card at the bottom shows your position in the selected category. A dash (—) means no personal result is available, not a score of zero.")
                    if showsSampleRankings { sampleNote }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .foregroundStyle(NanaPalette.warmWhite)
        .background(surface)
        .preferredColorScheme(.dark)
        .presentationDetents([.fraction(0.84), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("THE RANKING GUIDE")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.7)
                    .foregroundStyle(NanaPalette.electricLilac)
                Text("About rankings")
                    .font(.system(size: 24, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text("Find your way around the leaderboard.")
                    .font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close ranking guide")
                NanaAssetImage(assetKey: "nana.voice.voice_asset_008", contentMode: .fit)
                    .frame(width: 62, height: 46).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 22)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("01", title: "Three separate lists")
            VStack(alignment: .leading, spacing: 14) {
                categoryRow(.popularity, detail: "The overall popularity list.")
                categoryRow(.liveRoom, detail: "Rankings for live rooms.")
                categoryRow(.voiceRoom, detail: "Rankings for voice rooms.")
            }
            Text("Each category has its own results. A position in one list does not carry over to another.")
                .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(NanaPalette.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(NanaPalette.electricLilac.opacity(0.18), lineWidth: 1))
    }

    private func categoryRow(_ item: NanaRankingCategory, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.rawValue).font(.system(size: 14, weight: .semibold))
                if category == item {
                    Text("Viewing").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NanaPalette.electricLilac)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(NanaPalette.violet.opacity(0.2), in: Capsule())
                }
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .accessibilityElement(children: .combine)
    }

    private func explanation(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(number, title: title)
            Text(detail).font(.system(size: 13)).lineSpacing(4)
                .foregroundStyle(NanaPalette.mutedWhite)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private func sectionHeading(_ number: String, title: String) -> some View {
        HStack(spacing: 9) {
            Text(number).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(NanaPalette.electricLilac)
            Text(title).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
        }
    }

    private var sampleNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("About the current results").font(.system(size: 12, weight: .semibold))
            Text("This category currently shows sample results. These totals do not change your coin balance or establish your personal rank.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(NanaPalette.mutedWhite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4).padding(.top, 4)
    }

    private var footer: some View {
        Button { dismiss() } label: {
            Text("Got it").font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(NanaPalette.violet, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(surface)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5) }
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
    @EnvironmentObject private var contentStore: NanaContentStore
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
                    Label("\(contentStore.displayedViewerCount(for: room))", systemImage: "eye")
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
