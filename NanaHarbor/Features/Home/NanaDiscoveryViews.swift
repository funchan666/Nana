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
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            TextField("Search people, rooms, posts", text: $query)
                                .foregroundStyle(.white)
                                .nanaGlassField()
                            Button { showingFilters = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(.white).frame(width: 45, height: 45).background(NanaPalette.violet, in: RoundedRectangle(cornerRadius: 14)) }
                                .buttonStyle(.plain)
                        }
                        ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(NanaSearchFilter.SearchKind.allCases, id: \.self) { kind in NanaChip(title: kind.rawValue, isSelected: filter.kind == kind) { filter.kind = kind } } } }
                        if filter.kind == .all || filter.kind == .people { resultGroup(title: "People", profiles: matchingProfiles) }
                        if filter.kind == .all || filter.kind == .rooms { roomResults }
                        if filter.kind == .all || filter.kind == .posts { postResults }
                    }
                    .padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .sheet(isPresented: $showingFilters) { NanaSearchFilterView(filter: $filter) }
            .sheet(item: $selectedProfile) { profile in NanaUserProfileView(profile: profile) }
            .sheet(item: $selectedRoom) { room in NanaVoiceRoomDetailView(room: room) }
            .sheet(item: $selectedPost) { post in NanaPostDetailView(post: post) }
            .task { await contentStore.refresh(.search) }
        }
        .preferredColorScheme(.dark)
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
    @State private var comment = ""

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
                            Text(post.body).font(NanaType.body).foregroundStyle(.white.opacity(0.82)).lineSpacing(5)
                            Divider().overlay(NanaPalette.border).padding(.vertical, 8)
                            NanaSectionTitle(eyebrow: "Community", title: "Responses")
                            NanaEmptyState(title: "Responses unavailable", detail: "The published A-side contract provides post content only; no comment read or write endpoint is connected.", actionTitle: nil, action: nil)
                        }
                        .padding(20)
                    }
                    HStack(spacing: 8) {
                        TextField("Add a response…", text: $comment).foregroundStyle(.white).nanaGlassField()
                        Button { contentStore.explainUnavailable("Post responses") } label: { Image(systemName: "paperplane.fill").foregroundStyle(.white).frame(width: 44, height: 44).background(NanaPalette.violet, in: Circle()) }.buttonStyle(.plain)
                    }
                    .padding(12).background(NanaPalette.deepSpace.opacity(0.96))
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(NanaPalette.electricLilac) } }
            .overlay { if let notice = contentStore.actionNotice { AccountConsentNotice(notice: notice) { contentStore.dismissActionNotice() } } }
            .task { if post.id == "post-echoes" { await contentStore.refresh(.echoesPost) } }
        }
        .preferredColorScheme(.dark)
    }
}
