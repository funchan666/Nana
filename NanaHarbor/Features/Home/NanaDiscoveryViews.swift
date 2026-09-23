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

    private var matchingProfiles: [NanaProfile] {
        contentStore.filteredProfiles(for: filter).filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.handle.localizedCaseInsensitiveContains(query) }
    }
    private var matchingRooms: [NanaLiveRoom] {
        contentStore.filteredRooms(for: filter).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.hostName.localizedCaseInsensitiveContains(query) }
    }
    private var matchingPosts: [NanaPost] {
        contentStore.posts(for: filter).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                VStack(spacing: 0) {
                    searchHeader
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            searchField
                            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(NanaSearchFilter.SearchKind.allCases, id: \.self) { kind in NanaChip(title: kind.rawValue, isSelected: filter.kind == kind) { filter.kind = kind } } } }
                            if filter.kind == .all || filter.kind == .people { resultGroup(title: "People", profiles: matchingProfiles) }
                            if filter.kind == .all || filter.kind == .rooms { roomResults }
                            if filter.kind == .all || filter.kind == .posts { postResults }
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingFilters) { NanaSearchFilterView(filter: $filter) }
            .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
            .fullScreenCover(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
            .sheet(item: $selectedPost) { post in NanaPostDetailView(post: post) }
            .task { await contentStore.refresh(.search) }
        }
        .preferredColorScheme(.dark)
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Button {
                searchFocused = false
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.07), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Back from search")
            Spacer(minLength: 0)
            Text("Search").font(.system(size: 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                searchFocused = false
                showingFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NanaPalette.electricLilac)
                    .frame(width: 36, height: 36)
                    .background(NanaPalette.violet.opacity(0.16), in: Circle())
                    .overlay(Circle().strokeBorder(NanaPalette.electricLilac.opacity(0.20), lineWidth: 0.5))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Search filters")
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15))
                .foregroundStyle(NanaPalette.mutedWhite).accessibilityHidden(true)
            TextField("Search people, rooms, posts", text: $query)
                .font(.system(size: 14)).foregroundStyle(.white)
                .focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("Search people, rooms and posts")
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                        .foregroundStyle(NanaPalette.mutedWhite)
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 2)
        .frame(minHeight: 50)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NanaPalette.border, lineWidth: 0.7))
    }

    @ViewBuilder private func resultGroup(title: String, profiles: [NanaProfile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NanaSectionTitle(eyebrow: "Search", title: title)
            if profiles.isEmpty { Text("No people match these filters.").font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite) }
            ForEach(profiles) { profile in
                Button { selectedProfile = profile } label: { NanaPersonRow(profile: profile, trailingTitle: profile.isConnected ? "Connected" : "Connect") { contentStore.toggleConnection(for: profile.id) } }
                    .buttonStyle(.plain)
            }
        }
        .padding(15)
        .nanaCard()
    }

    private var roomResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            NanaSectionTitle(eyebrow: "Search", title: "Rooms")
            ForEach(matchingRooms) { room in Button { selectedRoom = room } label: { HStack { NanaRoomArtwork(room: room, height: 72).frame(width: 108); VStack(alignment: .leading, spacing: 4) { Text(room.title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite); Text(room.hostName).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite) }; Spacer() }.padding(.vertical, 5) }.buttonStyle(.plain) }
        }
        .padding(15)
        .nanaCard()
    }

    private var postResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            NanaSectionTitle(eyebrow: "Search", title: "Posts")
            ForEach(matchingPosts) { post in Button { selectedPost = post } label: { VStack(alignment: .leading, spacing: 5) { Text(post.title).font(NanaType.bodyMedium).foregroundStyle(NanaPalette.warmWhite); Text(post.body).font(NanaType.caption).foregroundStyle(NanaPalette.mutedWhite).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }.buttonStyle(.plain) }
        }
        .padding(15)
        .nanaCard()
    }
}

private struct NanaSearchFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: NanaSearchFilter
    var body: some View {
        NavigationStack {
            ZStack {
                NanaBackdrop()
                Form {
                    Section("Age") {
                        Stepper("From \(filter.minimumAge)", value: $filter.minimumAge, in: 18...70)
                        Stepper("To \(filter.maximumAge)", value: $filter.maximumAge, in: 18...70)
                    }
                    Section("Region") {
                        Picker("Region", selection: $filter.region) { ForEach(["All regions", "Toronto", "London", "Paris", "New York", "Singapore"], id: \.self) { Text($0).tag($0) } }
                    }
                    Section("Language") {
                        Picker("Language", selection: $filter.language) { ForEach(["All languages", "English", "French", "Mandarin"], id: \.self) { Text($0).tag($0) } }
                    }
                    Section("Gender") {
                        Picker("Gender", selection: $filter.gender) { ForEach(["Any", "Female", "Male", "Non-binary"], id: \.self) { Text($0).tag($0) } }
                    }
                }
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct NanaPostDetailView: View {
    let post: NanaPost
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var showingComments = false
    @State private var safetyAction: NanaPostSafetyAction?
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
                            NanaPostSafetyButtons { safetyAction = $0 }
                            Text(post.body).font(NanaType.body).foregroundStyle(.white.opacity(0.82)).lineSpacing(5)
                            Divider().overlay(NanaPalette.border).padding(.vertical, 8)
                            NanaSectionTitle(eyebrow: "Community", title: "Responses")
                            ForEach(comments) { comment in NanaPostCommentRow(comment: comment) }
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
