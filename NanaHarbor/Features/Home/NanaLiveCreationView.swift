import SwiftUI
import UIKit

private struct NanaLiveCreationDraft: Codable {
    var title = ""
    var popularityTarget = "1548"
    var introduction = ""
    var isPublic = true
    var tags: [String] = []
    var coverData: Data?
}

struct NanaLiveCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentStore: NanaContentStore
    @State private var draft = NanaLiveCreationDraft()
    @State private var showingMediaSource = false
    @State private var coverAccountID: String?
    @State private var coverImage: UIImage?
    @State private var notice: AccountEntryNotice?
    @State private var validationMessage: String?
    @State private var restoredDraft = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, popularity, introduction }
    private let draftKey = "live-creation"
    private let labels = ["Chat", "Music", "Creative", "Late night", "Comedy", "Lifestyle"]
    private let fieldColor = Color(red: 0.065, green: 0.035, blue: 0.20)

    var body: some View {
        creationScreen
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled()
            .onAppear(perform: restoreDraft)
            .nanaMediaSource(isPresented: $showingMediaSource) { media in
                guard coverAccountID != nil, coverAccountID == contentStore.accountScope,
                      let data = media.photoData, let image = UIImage(data: data) else { media.discard(); return }
                draft.coverData = data
                coverImage = image
                validationMessage = nil
            }
    }

    private var creationScreen: some View {
        creationLayout
            .safeAreaInset(edge: .bottom, spacing: 0) { keyboardBar }
            .disabled(notice != nil)
            .overlay { noticeOverlay }
    }

    private var creationLayout: some View {
        ZStack {
            NanaTabBackdrop()
            VStack(spacing: 8) {
                header
                ScrollView(showsIndicators: false) {
                    creationForm
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var creationForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            coverPicker
            titleField
            popularityField
            introductionField
            publicSetting
            tagPicker
            validationFeedback
            startButton
            publishingAvailability
        }
        .font(.system(size: 13))
        .foregroundStyle(NanaPalette.warmWhite)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var titleField: some View {
        TextField("Please enter the live streaming theme", text: titleBinding)
            .focused($focusedField, equals: Field.title)
            .submitLabel(.next)
            .onSubmit { focusedField = .popularity }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Live streaming theme")
    }

    private var popularityField: some View {
        HStack(spacing: 12) {
            Text("Target popularity").foregroundStyle(NanaPalette.mutedWhite)
            Spacer(minLength: 0)
            TextField("1548", text: popularityBinding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: Field.popularity)
                .frame(width: 90)
                .accessibilityLabel("Target popularity")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var validationFeedback: some View {
        if let validationMessage {
            Text(validationMessage)
                .font(.system(size: 12))
                .foregroundStyle(NanaPalette.softPink)
                .accessibilityLabel("Please check: \(validationMessage)")
        }
    }

    private var startButton: some View {
        Button(action: prepareToStart) {
            Text("Start live streaming")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(NanaPalette.violet, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var publishingAvailability: some View {
        Text("Save your setup as a draft. Live broadcasting is not available yet.")
            .font(.system(size: 11))
            .foregroundStyle(NanaPalette.mutedWhite)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private var keyboardBar: some View {
        if focusedField != nil {
            HStack {
                Spacer()
                Button("Done") { focusedField = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 64, minHeight: 44)
            }
            .padding(.horizontal, 16)
            .background(fieldColor)
        }
    }

    @ViewBuilder private var noticeOverlay: some View {
        if let notice {
            AccountConsentNotice(notice: notice) { self.notice = nil }
        }
    }

    private var titleBinding: Binding<String> {
        Binding<String>(get: { draft.title }, set: { draft.title = String($0.prefix(60)) })
    }

    private var introductionBinding: Binding<String> {
        Binding<String>(get: { draft.introduction }, set: { draft.introduction = String($0.prefix(80)) })
    }

    private var popularityBinding: Binding<String> {
        Binding<String>(get: { draft.popularityTarget }, set: { value in
            let digits = value.filter { character in "0123456789".contains(character) }
            draft.popularityTarget = String(digits.prefix(7))
        })
    }

    private var header: some View {
        HStack {
            Button {
                focusedField = nil
                if saveDraft() { dismiss() }
            } label: {
                Image(systemName: "chevron.left.circle").font(.system(size: 21))
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("Save draft and close")
            Spacer()
            VStack(spacing: 5) {
                Text("LIVE").font(.system(size: 16, weight: .heavy).italic())
                Capsule().fill(NanaPalette.violet).frame(width: 24, height: 3)
            }
            Spacer()
            Button("Save") {
                focusedField = nil
                if saveDraft() {
                    notice = AccountEntryNotice(title: "Draft saved", explanation: "Your cover and room settings are saved on this device.")
                }
            }.font(.system(size: 13, weight: .semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 14)
    }

    private var coverPicker: some View {
        ZStack(alignment: .topTrailing) {
            Button { focusedField = nil; coverAccountID = contentStore.accountScope; showingMediaSource = true } label: {
                ZStack {
                    fieldColor
                    if let coverImage {
                        GeometryReader { geometry in
                            Image(uiImage: coverImage).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        }
                    } else {
                        VStack(spacing: 12) {
                            NanaAssetImage(assetKey: "nana.voice.voice_asset_037", contentMode: .fit)
                                .frame(width: 76, height: 76)
                            Text("Add Cover").font(.system(size: 13)).foregroundStyle(NanaPalette.mutedWhite)
                        }
                    }
                }
                .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain).accessibilityLabel(coverImage == nil ? "Add cover photo" : "Change cover photo")
            if coverImage != nil {
                Button {
                    draft.coverData = nil
                    coverImage = nil
                } label: {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_034", contentMode: .fit)
                        .frame(width: 22, height: 22).frame(width: 44, height: 44)
                }.buttonStyle(.plain).padding(4).accessibilityLabel("Remove cover photo")
            }
        }
    }

    private var introductionField: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if draft.introduction.isEmpty {
                    Text("Please enter the live streaming content")
                        .foregroundStyle(NanaPalette.mutedWhite).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: introductionBinding)
                    .scrollContentBackground(.hidden).frame(height: 108)
                    .focused($focusedField, equals: .introduction)
                    .accessibilityLabel("Live streaming content")
            }
            Text("\(draft.introduction.count)/80")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(NanaPalette.mutedWhite)
        }
        .padding(12).background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private var publicSetting: some View {
        HStack {
            Text("Whether to make public").foregroundStyle(NanaPalette.mutedWhite)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                publicChoice("YES", value: true)
                publicChoice("NO", value: false)
            }.background(.white.opacity(0.9), in: Capsule())
        }
        .padding(.horizontal, 12).frame(height: 52)
        .background(fieldColor, in: RoundedRectangle(cornerRadius: 18))
    }

    private func publicChoice(_ title: String, value: Bool) -> some View {
        Button { draft.isPublic = value } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .foregroundStyle(draft.isPublic == value ? Color.white : Color.gray)
                .frame(width: 42, height: 32)
                .background(draft.isPublic == value ? NanaPalette.violet : Color.clear, in: Capsule())
                .frame(height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(draft.isPublic == value ? [.isSelected] : [])
    }

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Select label")
                Spacer()
                Text("\(draft.tags.count)/3").foregroundStyle(NanaPalette.mutedWhite)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 0) {
                ForEach(labels, id: \.self) { label in
                    tagButton(label)
                }
            }
        }
    }

    private func tagButton(_ label: String) -> some View {
        let selected: Bool = draft.tags.contains(label)
        let textColor: Color = selected ? NanaPalette.electricLilac : NanaPalette.mutedWhite
        let borderColor: Color = selected ? NanaPalette.violet : NanaPalette.border
        let traits: AccessibilityTraits = selected ? .isSelected : []
        return Button { toggleTag(label) } label: {
            Text("# \(label)")
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .overlay(Capsule().stroke(borderColor))
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
    }

    private func toggleTag(_ label: String) {
        if draft.tags.contains(label) { draft.tags.removeAll { $0 == label } }
        else if draft.tags.count < 3 { draft.tags.append(label) }
        else { validationMessage = "Select up to three labels." }
    }

    private func restoreDraft() {
        guard !restoredDraft else { return }
        restoredDraft = true
        guard let data = contentStore.draft(for: draftKey).data(using: .utf8),
              let saved = try? JSONDecoder().decode(NanaLiveCreationDraft.self, from: data) else { return }
        draft = saved
        coverImage = saved.coverData.flatMap { UIImage(data: $0) }
    }

    private func saveDraft() -> Bool {
        guard let data = try? JSONEncoder().encode(draft), let value = String(data: data, encoding: .utf8),
              contentStore.saveDraft(value, for: draftKey) else {
            notice = AccountEntryNotice(title: "Draft not saved", explanation: "Please try again. Your current setup is still here.")
            contentStore.dismissActionNotice()
            return false
        }
        return true
    }

    private func prepareToStart() {
        focusedField = nil
        guard draft.coverData != nil else { validationMessage = "Add a cover photo first."; return }
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Enter a live streaming theme."; focusedField = .title; return
        }
        guard let target = Int(draft.popularityTarget), target > 0 else {
            validationMessage = "Enter a popularity target greater than zero."; focusedField = .popularity; return
        }
        guard !draft.tags.isEmpty else { validationMessage = "Choose at least one label."; return }
        validationMessage = nil
        guard saveDraft() else { return }
        // The published service exposes read routes only. Never create a fake live room.
        notice = AccountEntryNotice(title: "Live setup saved", explanation: "Your draft is ready. Live broadcasting is not available yet, so your camera and microphone have not been started and nothing has been published.")
    }

}
