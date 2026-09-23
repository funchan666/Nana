import SwiftUI

struct NanaDiscoverySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var query = ""
    @State private var filter = NanaSearchFilter()
    @State private var showingFilters = false
    @State private var selectedProfile: NanaProfile?
    @State private var selectedRoom: NanaLiveRoom?
    @State private var selectedPost: NanaPost?
    @FocusState private var searchFocused: Bool

    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingProfiles: [NanaProfile] {
        contentStore.filteredProfiles(for: filter).filter {
            searchTerm.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchTerm) || $0.handle.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    private var matchingRooms: [NanaLiveRoom] {
        contentStore.filteredRooms(for: filter).filter {
            searchTerm.isEmpty || $0.title.localizedCaseInsensitiveContains(searchTerm) || $0.hostName.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    private var matchingPosts: [NanaPost] {
        contentStore.posts(for: filter).filter {
            searchTerm.isEmpty || $0.title.localizedCaseInsensitiveContains(searchTerm) || $0.body.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    private var hasCustomFilters: Bool {
        var comparable = filter
        comparable.kind = .all
        return comparable != NanaSearchFilter()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
                VStack(spacing: 10) {
                    searchField
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(NanaSearchFilter.SearchKind.allCases, id: \.self) { kind in
                                NanaDiscoveryChoice(title: kind.rawValue, selected: filter.kind == kind) { filter.kind = kind }
                            }
                        }
                    }.frame(height: 44)
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        if searchTerm.isEmpty && !searchFocused { discoveryIntro }
                        if filter.kind == .all || filter.kind == .people { peopleResults }
                        if filter.kind == .all || filter.kind == .rooms { roomResults }
                        if filter.kind == .all || filter.kind == .posts { postResults }
                    }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 28)
                }
                .clipped().scrollDismissesKeyboard(.interactively)
            }
            .background(NanaPalette.midnight.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingFilters) {
                NanaSearchFilterView(filter: $filter)
                    .presentationDetents([.large]).presentationDragIndicator(.hidden)
            }
            .fullScreenCover(item: $selectedProfile) { NanaUserProfileView(profile: $0) }
            .fullScreenCover(item: $selectedRoom) { NanaVoiceRoomDetailView(room: $0) }
            .sheet(item: $selectedPost) { NanaPostDetailView(post: $0) }
            .task { await contentStore.refresh(.search) }
        }
        .foregroundStyle(NanaPalette.warmWhite).preferredColorScheme(.dark)
        .overlay {
            if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Button { searchFocused = false; dismiss() } label: {
                NanaAssetImage(assetKey: "nana.voice.voice_asset_030", contentMode: .fit)
                    .frame(width: 26, height: 26).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("Back from search")
            Text("Search").font(.system(size: 24, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { searchFocused = false; showingFilters = true } label: {
                HStack(spacing: 3) {
                    Image("NanaFilterIllustration").resizable().scaledToFit().frame(width: 34, height: 34)
                    Text(hasCustomFilters ? "Filtered" : "Filters").font(.system(size: 12, weight: .semibold))
                }.frame(minHeight: 44).padding(.horizontal, 5).contentShape(Rectangle())
            }.accessibilityLabel(hasCustomFilters ? "Edit active search filters" : "Search filters")
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image("NanaSearchIllustration").resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            TextField("People, rooms & stories", text: $query, prompt: Text("People, rooms & stories").foregroundStyle(NanaPalette.mutedWhite))
                .font(.system(size: 14)).focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }.accessibilityLabel("Search people, rooms and posts")
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: {
                    NanaAssetImage(assetKey: "nana.photo.photo_asset_005", contentMode: .fit)
                        .frame(width: 16, height: 16).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12).padding(.trailing, query.isEmpty ? 12 : 0).frame(minHeight: 54)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }

    private var discoveryIntro: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Text("A little curiosity.").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Find a new connection.").font(.system(size: 15, weight: .medium)).foregroundStyle(NanaPalette.electricLilac)
                Text("People, conversations and places to belong.")
                    .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image("NanaSearchIllustration").resizable().scaledToFit().frame(width: 102, height: 112).accessibilityHidden(true)
        }.padding(.vertical, 6)
    }

    private var peopleResults: some View {
        VStack(alignment: .leading, spacing: 13) {
            resultHeading("People", subtitle: "Start with someone new", count: matchingProfiles.count)
            if matchingProfiles.isEmpty { emptyResults("No people found", detail: "Try another name or broaden your filters.") }
            else if filter.kind == .all {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(matchingProfiles) { profile in personCard(profile).frame(width: 148) }
                    }
                }.frame(height: 236)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 14) {
                    ForEach(matchingProfiles) { personCard($0) }
                }
            }
        }
    }

    private func personCard(_ profile: NanaProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { searchFocused = false; selectedProfile = profile } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if let asset = profile.avatarAssetKey { NanaMediaPreview(assetKey: asset) }
                        else { NanaAvatarView(title: profile.displayName, assetKey: nil, size: 80) }
                    }.frame(height: 126).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 15)).contentShape(Rectangle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(profile.region.isEmpty ? "@" + profile.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")) : profile.region)
                            .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                    }.padding(.horizontal, 10)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("View \(profile.displayName)'s profile")
            Button { contentStore.toggleConnection(for: profile.id) } label: {
                NanaAssetImage(assetKey: contentStore.isFollowing(profile.id) ? "nana.voice.voice_asset_101" : "nana.voice.voice_asset_100", contentMode: .fit)
                    .frame(height: 27).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 10)
                .accessibilityLabel(contentStore.isFollowing(profile.id) ? "Unfollow \(profile.displayName)" : "Follow \(profile.displayName)")
        }.padding(5).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    private var roomResults: some View {
        VStack(alignment: .leading, spacing: 13) {
            resultHeading("Rooms", subtitle: "Find your kind of conversation", count: matchingRooms.count)
            if matchingRooms.isEmpty { emptyResults("No rooms found", detail: "Try a topic or a host's name.") }
            LazyVStack(spacing: 12) {
                ForEach(matchingRooms) { room in
                    Button { searchFocused = false; selectedRoom = room } label: {
                        HStack(spacing: 13) {
                            Group {
                                if let asset = room.streamAssetKey ?? room.hostAvatarAssetKey { NanaMediaPreview(assetKey: asset) }
                                else { NanaAvatarView(title: room.hostName, assetKey: nil, size: 72) }
                            }.frame(width: 92, height: 106).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
                            VStack(alignment: .leading, spacing: 7) {
                                Text(room.streamSourceType == "simulatedReplay" ? "REPLAY" : room.roomState.uppercased())
                                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(NanaPalette.softPink).lineLimit(1)
                                Text(room.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                                Text(room.hostName).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(1)
                                Text(room.category).font(.system(size: 11, weight: .medium)).foregroundStyle(NanaPalette.electricLilac).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            NanaAssetImage(assetKey: "nana.voice.voice_asset_033", contentMode: .fit)
                                .frame(width: 8, height: 13).padding(.trailing, 4).accessibilityHidden(true)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var postResults: some View {
        VStack(alignment: .leading, spacing: 13) {
            resultHeading("Posts", subtitle: "Thoughts worth sharing", count: matchingPosts.count)
            if matchingPosts.isEmpty { emptyResults("No posts found", detail: "Try a different word or a shorter phrase.") }
            ForEach(matchingPosts) { post in
                Button { searchFocused = false; selectedPost = post } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(post.category.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1)
                            .foregroundStyle(NanaPalette.softPink).lineLimit(1)
                        Text(post.title).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(2)
                        Text(post.body).font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite).lineLimit(2)
                        Text(post.authorName).font(.system(size: 11, weight: .medium)).foregroundStyle(NanaPalette.electricLilac)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func resultHeading(_ title: String, subtitle: String, count: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer()
            Text("\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(NanaPalette.electricLilac).padding(.horizontal, 10).padding(.vertical, 5)
        }
    }

    private func emptyResults(_ title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image("NanaSearchIllustration").resizable().scaledToFit().frame(width: 58, height: 58).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct NanaDiscoveryChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? NanaPalette.warmWhite : NanaPalette.mutedWhite)
                .padding(.horizontal, 15).frame(minHeight: 44).frame(maxWidth: .infinity)
                .background {
                    if selected { Image("NanaCheckInGuideButton").resizable().allowsHitTesting(false) }
                    else { Color.white.opacity(0.045).clipShape(Capsule()).padding(.vertical, 4) }
                }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NanaSearchFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @Binding var filter: NanaSearchFilter
    @State private var draft: NanaSearchFilter

    init(filter: Binding<NanaSearchFilter>) {
        _filter = filter
        var initial = filter.wrappedValue
        initial.minimumAge = min(70, max(18, initial.minimumAge))
        initial.maximumAge = min(70, max(initial.minimumAge, initial.maximumAge))
        _draft = State(initialValue: initial)
    }

    private var regions: [String] { options(contentStore.visibleProfiles.map(\.region), current: draft.region, all: "All regions") }
    private var languages: [String] { options(contentStore.visibleProfiles.map(\.language), current: draft.language, all: "All languages") }
    private let genders = ["Any", "Female", "Male", "Non-binary"]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Filters").font(.system(size: 17, weight: .semibold))
                HStack {
                    Button("Cancel") { dismiss() }.font(.system(size: 14, weight: .medium)).frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button("Reset") { resetDraft() }.font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NanaPalette.electricLilac).frame(minWidth: 44, minHeight: 44)
                }
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 10)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Your kind\nof connection.").font(.system(size: 27, weight: .bold, design: .rounded))
                            Text("A few details. A better fit.").font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image("NanaFilterIllustration").resizable().scaledToFit().frame(width: 106, height: 118).accessibilityHidden(true)
                    }
                    ageSection
                    selectionSection("Region", detail: "Where they are", options: regions, selection: $draft.region)
                    selectionSection("Language", detail: "Find a common language", options: languages, selection: $draft.language)
                    selectionSection("Gender", detail: "Who you'd like to meet", options: genders, selection: $draft.gender)
                    Text("These filters refine people and room hosts. Posts are matched by your search words.")
                        .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite).lineSpacing(3)
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 20)
            }.clipped()
            Button {
                filter = draft
                dismiss()
            } label: {
                Text("Apply filters").font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 58)
                    .background { Image("NanaCheckInGuideButton").resizable().allowsHitTesting(false) }
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        }
        .background(NanaPalette.midnight.ignoresSafeArea())
        .foregroundStyle(NanaPalette.warmWhite).preferredColorScheme(.dark)
    }

    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeading("Age range", detail: "Adults 18 and over")
            HStack(spacing: 12) {
                ageControl("From", value: draft.minimumAge, minimum: 18, maximum: draft.maximumAge) { draft.minimumAge = $0 }
                ageControl("To", value: draft.maximumAge, minimum: draft.minimumAge, maximum: 70) { draft.maximumAge = $0 }
            }
            HStack(spacing: 5) {
                agePreset("18–25", lower: 18, upper: 25)
                agePreset("26–35", lower: 26, upper: 35)
                agePreset("36–45", lower: 36, upper: 45)
                agePreset("18–70", lower: 18, upper: 70)
            }
        }
    }

    private func ageControl(_ label: String, value: Int, minimum: Int, maximum: Int, setValue: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 7) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(NanaPalette.mutedWhite)
            Text("\(value)").font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
            HStack(spacing: 16) {
                ageStep(asset: "115", label: "Decrease \(label.lowercased()) age", enabled: value > minimum) { setValue(max(minimum, value - 1)) }
                ageStep(asset: "113", label: "Increase \(label.lowercased()) age", enabled: value < maximum) { setValue(min(maximum, value + 1)) }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
    }

    private func ageStep(asset: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NanaAssetImage(assetKey: "nana.voice.voice_asset_\(asset)", contentMode: .fit)
                .frame(width: 25, height: 25).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.25).accessibilityLabel(label)
    }

    private func agePreset(_ title: String, lower: Int, upper: Int) -> some View {
        NanaDiscoveryChoice(title: title, selected: draft.minimumAge == lower && draft.maximumAge == upper) {
            draft.minimumAge = lower
            draft.maximumAge = upper
        }
    }

    private func selectionSection(_ title: String, detail: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading(title, detail: detail)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 7)], spacing: 4) {
                ForEach(options, id: \.self) { option in
                    NanaDiscoveryChoice(title: option, selected: selection.wrappedValue == option) { selection.wrappedValue = option }
                }
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
        }
    }

    private func options(_ values: [String], current: String, all: String) -> [String] {
        let choices = Set(values.filter { !$0.isEmpty && $0 != all } + (current == all ? [] : [current]))
        return [all] + choices.sorted()
    }

    private func resetDraft() {
        let kind = draft.kind
        draft = NanaSearchFilter()
        draft.kind = kind
    }
}

struct NanaPostDetailView: View {
    let post: NanaPost
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingComments = false
    @State private var safetyAction: NanaPostSafetyAction?
    @State private var commentSafetySelection: NanaCommentSafetySelection?
    private var discussion: NanaPostDiscussion { contentStore.discussion(for: post) }
    private var comments: [NanaPostComment] { contentStore.comments(for: discussion) }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 15) {
                            Text(post.category.uppercased()).font(NanaType.stamp).tracking(1.2).foregroundStyle(NanaPalette.softPink)
                            Text(post.title).font(NanaType.hero).foregroundStyle(NanaPalette.warmWhite)
                            Text("By \(post.authorName) · \(post.publishedLabel)").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite)
                            NanaSafetyOptionsButton { safetyAction = $0 }
                            Text(post.body).font(NanaType.body).foregroundStyle(.white.opacity(0.82)).lineSpacing(5)
                            Divider().overlay(NanaPalette.border).padding(.vertical, 8)
                            NanaSectionTitle(eyebrow: "Community", title: "Responses")
                            ForEach(comments) { comment in
                                NanaPostCommentRow(comment: comment) { action in
                                    commentSafetySelection = NanaCommentSafetySelection(context: contentStore.discussion(for: comment, in: discussion), action: action)
                                }
                            }
                            Button("View all \(comments.count) comments") { showingComments = true }
                                .font(NanaType.caption).foregroundStyle(NanaPalette.electricLilac).frame(minHeight: 44)
                        }
                        .padding(20)
                    }
                    Button { showingComments = true } label: {
                        HStack {
                            Image(systemName: "text.bubble")
                            Text("Add a comment…")
                            Spacer()
                            Text("\(comments.count)")
                        }.padding(16).foregroundStyle(.white)
                    }.buttonStyle(.plain).background(NanaPalette.deepSpace)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) }
            }
            .sheet(isPresented: $showingComments) { NanaPostCommentsSheet(context: discussion) }
            .sheet(item: $commentSafetySelection) { selection in
                NanaPostSafetySheet(context: selection.context, initialAction: selection.action) { commentSafetySelection = nil }
            }
            .sheet(item: $safetyAction) { action in
                NanaPostSafetySheet(context: discussion, initialAction: action) { dismiss() }
            }
            .onChange(of: contentStore.safetyDismissalID) { _, _ in
                if contentStore.post(with: post.id) == nil { dismiss() }
            }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
            .task { if post.id == "post-echoes" { await contentStore.refresh(.echoesPost) } }
        }
        .preferredColorScheme(.dark)
    }
}
