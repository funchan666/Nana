import SwiftUI
import UIKit

struct NanaProfileCompletionView: View {
    @EnvironmentObject private var sessionStore: NanaSessionStore
    let goBack: () -> Void

    @State private var displayName = ""
    @State private var gender = ""
    @State private var country = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var selectedInterests: Set<String> = []
    @State private var avatarData: Data?
    @State private var showingMediaSource = false
    @State private var notice: AccountEntryNotice?

    private let interestOptions = ["Short walks", "Plant cuttings", "New cafés", "Mending", "Small concerts", "Good questions"]
    private let countries = ["United States", "Canada", "United Kingdom", "Australia", "New Zealand", "Other"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AccountEntryAppearance.linkLilac)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR SHORE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(AccountEntryAppearance.mutedText)
                    Text("A few things\nabout you.")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("This helps Nana make the first few moments feel like yours.")
                        .font(.system(size: 14))
                        .foregroundStyle(AccountEntryAppearance.mutedText)
                        .lineSpacing(3)
                }
                avatarSection
                profileField(title: "Name", placeholder: "Your name", value: $displayName)
                genderSection
                profileField(title: "Country", placeholder: "Choose your country", value: $country, picker: countries)
                DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .datePickerStyle(.compact)
                    .tint(AccountEntryAppearance.linkLilac)
                    .padding(.vertical, 10)
                interestSection
                Button(action: finishProfile) {
                    Text("Next")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(AccountEntryAppearance.violet, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(.container)
        .background { AccountArtworkSurface(artworkName: "NanaPlainArtwork") }
        .background(.black)
        .overlay {
            if let notice {
                AccountConsentNotice(notice: notice) { self.notice = nil }
            }
        }
        .onAppear {
            if displayName.isEmpty { displayName = sessionStore.pendingIdentity?.displayName ?? "" }
        }
        .nanaMediaSource(isPresented: $showingMediaSource) { media in
            avatarData = media.photoData
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            Group {
                if let avatarData, let image = UIImage(data: avatarData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    NanaAssetImage(assetKey: "nana.asset.NanaChatPhotoIcon", contentMode: .fit)
                        .frame(width: 60, height: 60)
                }
            }
            .frame(width: 112, height: 112)
            .background(NanaPalette.deepSpace, in: Circle())
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
            .onTapGesture { showingMediaSource = true }
            .accessibilityAddTraits(.isButton).accessibilityLabel("Choose profile photo")
            Button("Choose photo") { showingMediaSource = true }
                .buttonStyle(ProfileSmallButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Gender").font(.system(size: 12)).foregroundStyle(AccountEntryAppearance.mutedText)
            HStack(spacing: 10) {
                ForEach(["Male", "Female", "Prefer not to say"], id: \.self) { option in
                    Button {
                        gender = option
                    } label: {
                        Text(option)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(gender == option ? .white : AccountEntryAppearance.mutedText)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 42)
                            .background(gender == option ? AccountEntryAppearance.violet : .clear, in: Capsule())
                            .overlay(Capsule().stroke(gender == option ? AccountEntryAppearance.violet : .white.opacity(0.28), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func profileField(title: String, placeholder: String, value: Binding<String>, picker: [String]? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(AccountEntryAppearance.mutedText)
            if let picker {
                Menu {
                    ForEach(picker, id: \.self) { value in
                        Button(value) { self.country = value }
                    }
                } label: {
                    HStack {
                        Text(value.wrappedValue.isEmpty ? placeholder : value.wrappedValue)
                            .foregroundStyle(value.wrappedValue.isEmpty ? AccountEntryAppearance.mutedText : .white)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            } else {
                TextField(placeholder, text: value)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(AccountEntryAppearance.linkLilac)
                    .textInputAutocapitalization(.words)
                    .frame(minHeight: 44)
            }
            Rectangle().fill(AccountEntryAppearance.fieldRule).frame(height: 0.5)
        }
    }

    private var interestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A few tags").font(.system(size: 12)).foregroundStyle(AccountEntryAppearance.mutedText)
            FlowTagLayout(tags: interestOptions, selected: selectedInterests) { selected in
                if selectedInterests.contains(selected) { selectedInterests.remove(selected) } else { selectedInterests.insert(selected) }
            }
        }
    }

    private func finishProfile() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !gender.isEmpty, !country.isEmpty, !selectedInterests.isEmpty else {
            notice = AccountEntryNotice(title: "A little more to fill in", explanation: "Add your name, gender, country, and at least one tag before entering Nana.")
            return
        }
        do {
            try sessionStore.completeProfile(displayName: trimmedName, gender: gender, country: country, birthDate: birthDate, interests: Array(selectedInterests).sorted(), avatarData: avatarData)
        } catch {
            notice = AccountEntryNotice(title: "Couldn't save your profile", explanation: error.localizedDescription)
        }
    }
}

private struct ProfileSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 40)
            .background(AccountEntryAppearance.violet.opacity(configuration.isPressed ? 0.62 : 0.82), in: Capsule())
    }
}

private struct FlowTagLayout: View {
    let tags: [String]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 9)], spacing: 9) {
            ForEach(tags, id: \.self) { tag in
                Button { toggle(tag) } label: {
                    Text(tag)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected.contains(tag) ? .white : AccountEntryAppearance.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(selected.contains(tag) ? AccountEntryAppearance.violet : .clear, in: Capsule())
                        .overlay(Capsule().stroke(selected.contains(tag) ? AccountEntryAppearance.violet : .white.opacity(0.24), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
