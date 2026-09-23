import SwiftUI
import UIKit

/// Curated local discussion content, separate from the read-only service payload.
enum NanaPostCommentSamples {
    private static let videoResponses: [String: [String]] = [
        "ariffathulhakim": ["The red roofs under those trees look like a storybook.", "I would happily take the long way home through this street.", "That little corner has so much character."],
        "berniemor": ["The confidence after that opening caption!", "The red cap really completes this outfit.", "The timing of that look at the camera got me.", "The bag deserves its own outfit check."],
        "capt.carterbrown": ["The water looks so peaceful out there.", "Was that a dog swimming behind you?", "A river day sounds better than all my weekend plans."],
        "coletrotta": ["Those mountains make the road look tiny.", "The way the road curves through the valley is incredible.", "That low camera angle makes the movement feel so fast."],
        "escapetolandscapes": ["Cycling with that view would make every hill worth it.", "The blue sky and green slopes are such a beautiful combination.", "Adding a mountain bike ride to my travel wish list.", "I would stop for photos every few minutes."],
        "harvon.x": ["A tiny house surrounded by sunflowers. What a dream.", "The whole hillside looks golden.", "I wonder how quiet it gets there in the evening."],
        "iangblack": ["The detail on that stone monument is amazing.", "The curved steps make such a good frame for this shot.", "Cloudy weather really suits this architecture."],
        "inga_galeeva": ["That looks like a well-earned break on the trail.", "Sunglasses, mountain air, and nowhere to rush.", "The forest in the background looks endless."],
        "josee.steelman": ["Your smile is contagious in this clip.", "This has the energy of catching up with a friend.", "Love a little walking update like this."],
        "lilyrowland1": ["Those sunglasses are such a good shape.", "A city walk and a spontaneous outfit check. Love it.", "The buildings behind you make a lovely backdrop.", "Simple black tee, great styling."],
        "maialopezr": ["That red knit is the perfect pop of color.", "The sunglasses and zip-up combination really works.", "This makes me want to refresh my autumn wardrobe."],
        "mark_pnw": ["The reflection is almost too perfect to be real.", "That silhouette on the rock makes the whole scene.", "I could watch this quiet lake for ages.", "The soft morning light is everything here."],
        "matti_af": ["Such a relaxed little street scene.", "The bicycle and the shopfronts give this so much atmosphere.", "This feels like a weekend with no plans."],
        "megaamerican": ["The ocean behind you looks powerful.", "That blue water is mesmerizing.", "The contrast between the white outfit and the waves is lovely."],
        "mickjaggedd": ["The wired headphones are part of the look.", "Those shoes pull the whole outfit together.", "A walking outfit check is such a fun angle."],
        "mkaaloha": ["You two have such an easy energy together.", "The cap and beanie combination is adorable.", "This feels like being invited along on a walk.", "The evening light makes this so warm."],
        "radovantravels": ["That trail looks like a proper adventure.", "The little details make it feel like we are walking with you.", "Where does that path lead?"]
    ]

    static func comments(for context: NanaPostDiscussion) -> [NanaPostComment] {
        let bodies: [String]
        if let asset = context.videoAssetKey,
           let entry = videoResponses.first(where: { asset.hasPrefix("nana.video.\($0.key)_") }) {
            bodies = entry.value
        } else {
            switch context.key {
            case "post-echoes": bodies = ["Being allowed to finish a thought without being interrupted.", "A host who notices the quiet people makes all the difference.", "For me it is knowing I can just listen, too.", "Leaving space for the next voice is such a lovely way to put it."]
            case "post-studio": bodies = ["Slow afternoons need a little piano in the background.", "Saving this for my Sunday listening session.", "What would you choose as the opening track?"]
            case "post-question": bodies = ["A stranger once told me that rest does not need to be earned.", "Someone on a train taught me to ask better questions.", "An unexpected conversation helped me try something new.", "I still remember a kind word from a person I never saw again."]
            default: bodies = ["“\(context.title)” gives me something to think about today.", "I would love to hear more about what inspired this, \(context.authorName).", "There is room for a whole conversation around this post."]
            }
        }
        let names = ["Ava Monroe", "Jules Harper", "Mira Laurent", "Noah Reed", "Lin Wei"]
        let photos = ["nana.pic.Dc0SA4UiUy3", "nana.pic.Dc0XoT9DgeO", "nana.pic.Dc1CvDfCCHN", "nana.pic.Dc1Ii5HACCq", "nana.pic.Dc1UKGTDL1J"]
        let profileIDs = ["profile-ava", "profile-jules", "profile-mira", "profile-noah", "profile-lin"]
        let participants = profileIDs.indices.filter { profileIDs[$0] != context.authorID }
        let seed = Int(context.key.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 1000)
        return bodies.enumerated().map { index, body in
            let person = participants[(seed + index) % participants.count]
            return NanaPostComment(id: "\(context.key)-comment-\(index)", authorID: profileIDs[person],
                                   authorName: names[person], avatarAssetKey: photos[person], body: body,
                                   timeLabel: "\(3 + (seed + index * 7) % 55)m ago")
        }
    }
}

struct NanaPostCommentsSheet: View {
    let context: NanaPostDiscussion
    var focusComposer = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var comments: [NanaPostComment] { contentStore.comments(for: context) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Comments").font(.system(size: 19, weight: .heavy).italic())
                Text("\(comments.count)").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(NanaPalette.violet.opacity(0.22), in: Capsule())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close comments")
            }.padding(.horizontal, 18).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(comments) { comment in NanaPostCommentRow(comment: comment) }
                    }.padding(18)
                }
                .onChange(of: comments.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .foregroundStyle(.white).buttonStyle(.plain)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0.075, green: 0.055, blue: 0.10))
        .task {
            draft = contentStore.draft(for: "post-comment-\(context.key)")
            if contentStore.personal.drafts["post-comment-\(context.key)"] == nil, let asset = context.videoAssetKey {
                draft = contentStore.draft(for: "video-comment-\(asset)")
            }
            focused = focusComposer
        }
        .onChange(of: draft) { _, value in if value.count > 500 { draft = String(value.prefix(500)) } }
        .onDisappear { _ = contentStore.saveDraft(draft, for: "post-comment-\(context.key)") }
        .overlay {
            if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .lineLimit(1...4).font(.system(size: 14)).focused($focused)
                .padding(13).background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20))
            Button {
                if contentStore.addComment(draft, to: context, senderName: sessionStore.activeProfile?.displayName ?? "You") {
                    draft = ""; focused = false
                }
            } label: {
                Image(systemName: "paperplane.fill").frame(width: 44, height: 44)
                    .background(NanaPalette.violet, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send comment")
        }
        .padding(14).background(Color(red: 0.075, green: 0.055, blue: 0.10))
    }
}

struct NanaPostCommentRow: View {
    let comment: NanaPostComment
    @EnvironmentObject private var contentStore: NanaContentStore
    @EnvironmentObject private var sessionStore: NanaSessionStore
    private var liked: Bool { contentStore.preference("comment-like-\(comment.id)", default: false) }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                Text(comment.authorName).font(.system(size: 13, weight: .semibold))
                Text(comment.body).font(.system(size: 13)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).foregroundStyle(.white.opacity(0.9))
                Text(comment.timeLabel).font(.system(size: 10)).foregroundStyle(NanaPalette.mutedWhite)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { contentStore.setPreference("comment-like-\(comment.id)", value: !liked) } label: {
                Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 15))
                    .foregroundStyle(liked ? NanaPalette.neonPink : NanaPalette.mutedWhite)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(liked ? "Unlike comment" : "Like comment")
        }
    }

    private var avatar: some View {
        Group {
            if comment.authorID == "local-account", let data = sessionStore.activeProfile?.avatarData,
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NanaAvatarView(title: comment.authorName, assetKey: comment.avatarAssetKey, size: 36)
            }
        }.frame(width: 36, height: 36).clipShape(Circle())
    }
}

enum NanaPostSafetyAction: String, Identifiable {
    case options, report, block
    var id: String { rawValue }
}

struct NanaPostSafetyButtons: View {
    var subject = "post"
    let perform: (NanaPostSafetyAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button("Report", symbol: "flag", action: .report, tint: .white)
            button("Block", symbol: "person.slash", action: .block, tint: NanaPalette.softPink)
        }
        .buttonStyle(.plain)
    }

    private func button(_ title: String, symbol: String, action: NanaPostSafetyAction, tint: Color) -> some View {
        Button { perform(action) } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
                .padding(.horizontal, 13).frame(minHeight: 44)
                .background(.black.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
        }
        .accessibilityLabel(action == .report ? "Report \(subject)" : "Block user")
    }
}

struct NanaPostSafetySheet: View {
    let context: NanaPostDiscussion
    let didHide: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var page = "options"
    @State private var reason = "Harassment or bullying"
    @State private var finished = false
    @State private var successNotice: AccountEntryNotice?
    private let reasons = ["Harassment or bullying", "Hateful content", "Sexual content", "Violence or dangerous acts", "Spam or scam", "Other"]

    init(context: NanaPostDiscussion, initialAction: NanaPostSafetyAction = .options, didHide: @escaping () -> Void) {
        self.context = context
        self.didHide = didHide
        _page = State(initialValue: initialAction.rawValue)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(title).font(.system(size: 19, weight: .heavy).italic())
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close options")
                }
                if page == "options" {
                    action("Report \(subject)", subtitle: "Choose a reason and hide this content", symbol: "flag", tint: NanaPalette.electricLilac) { page = "report" }
                    action("Block user", subtitle: context.authorName, symbol: "person.slash", tint: NanaPalette.softPink) { page = "block" }
                } else if page == "report" {
                    ForEach(reasons, id: \.self) { item in
                        Button { reason = item } label: {
                            HStack {
                                Text(item).font(.system(size: 14))
                                Spacer()
                                Image(systemName: reason == item ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(reason == item ? NanaPalette.electricLilac : NanaPalette.mutedWhite)
                            }.frame(minHeight: 44)
                        }
                    }
                    primary("Report & hide \(subject)") {
                        if contentStore.reportContent(context, reason: reason) {
                            successNotice = AccountEntryNotice(title: "Report saved", explanation: "Your report has been saved. This content is now hidden from your lists.")
                        }
                    }
                } else if page == "block" {
                    Text("Block \(context.authorName)? Their profile, posts, rooms, comments and messages will be hidden.")
                        .font(.system(size: 15)).foregroundStyle(NanaPalette.mutedWhite)
                    primary("Block user") {
                        if contentStore.blockPostAuthor(context) {
                            successNotice = AccountEntryNotice(title: "User blocked", explanation: "\(context.authorName) and their related content are now hidden. Your choice has been saved.")
                        }
                    }
                    Button("Cancel") { page = "options" }.frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(20).foregroundStyle(.white).buttonStyle(.plain)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(successNotice != nil ? 420 : (page == "report" ? 530 : 300))])
        .presentationDragIndicator(.visible).presentationBackground(NanaPalette.deepSpace)
        .interactiveDismissDisabled(successNotice != nil)
        .overlay {
            if let successNotice {
                AccountConsentNotice(notice: successNotice, dismissNotice: { finish() }, dimsBackground: false)
            } else if let notice = contentStore.actionNotice {
                AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() }
            }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        contentStore.completeSafetyAction()
        didHide()
    }

    private var subject: String { context.kind.rawValue }

    private var title: String {
        switch page {
        case "report": return "Report \(subject)"
        case "block": return "Block user?"
        default: return context.kind == .post ? "Post options" : "Safety options"
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48).background(NanaPalette.violet, in: Capsule())
        }
    }

    private func action(_ title: String, subtitle: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            }.padding(14).frame(minHeight: 64).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
