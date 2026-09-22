import SwiftUI

/// Local presentation effects for bundled video replays. These events are never
/// persisted as messages, added to live membership, or sent to the coin ledger.
@MainActor
struct NanaRoomReplayActivityView: View {
    let room: NanaLiveRoom
    let recordedMessages: [NanaRoomChatMessage]
    let audience: [NanaReplayAudienceMember]
    let isActive: Bool
    var hidesGiftEffects = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lines: [ReplayLine] = []
    @State private var gift: ReplayGift?
    @State private var tick = 0
    @State private var sequence = 0

    private struct ReplayLine: Identifiable {
        let id: Int
        let name: String
        let text: String
    }
    private struct ReplayGift: Identifiable {
        let id: Int
        let sender: NanaReplayAudienceMember
        let item: NanaGift
        let quantity: Int
    }

    private var seed: Int {
        Int(room.id.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 10000)
    }
    private var phrases: [String] {
        let common = ["Love the energy here!", "Sending a little good energy your way.", "That made me smile.", "Such a lovely moment."]
        switch room.category {
        case "Music": return ["This is going on my playlist.", "One more song, please!", "The rhythm is everything.", "Headphones on. I'm staying here."] + common
        case "Creative": return ["Where do you find your inspiration?", "That detail is so good.", "Love seeing the process.", "Keep creating. This is beautiful."] + common
        case "Late night": return ["Perfect company for a quiet night.", "The best conversations happen late.", "Taking a little break here.", "This feels like a cozy corner."] + common
        default: return ["Hello from my little corner!", "What's everyone up to today?", "Glad I found this room.", "Let's hear another story."] + common
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Room activity")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            ZStack(alignment: .leading) {
                if let gift, !hidesGiftEffects {
                    giftBanner(gift)
                        .id(gift.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(height: hidesGiftEffects ? 0 : 50, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Keep it kind. Enjoy the room and respect each other.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                // Keep available room messages visible instead of replacing them
                // with effects. Demo rows use the remaining space in the rail.
                ForEach(Array(recordedMessages.suffix(2))) { message in
                    (Text("\(message.senderName): ").foregroundColor(NanaPalette.neonPink) + Text(message.body).foregroundColor(.white))
                        .font(.system(size: 10)).lineLimit(2)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(Array(lines.suffix(recordedMessages.isEmpty ? 3 : 1))) { line in
                    (Text("\(line.name): ").foregroundColor(NanaPalette.neonPink) + Text(line.text).foregroundColor(.white))
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .task(id: isActive) {
            guard isActive else { return }
            if lines.isEmpty {
                for _ in 0..<3 { appendLine() }
                showGift()
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                    tick += 1
                    if tick.isMultiple(of: 2) { appendLine() }
                    if tick.isMultiple(of: 5) { showGift() }
                    else if tick % 5 == 3 { gift = nil }
                }
            }
        }
    }

    private func giftBanner(_ event: ReplayGift) -> some View {
        HStack(spacing: 7) {
            NanaAvatarView(title: event.sender.displayName, assetKey: event.sender.avatarAssetKey, size: 29)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.sender.displayName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text("\(event.item.title) · Preview").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
            NanaAssetImage(assetKey: event.item.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit)
                .frame(width: 36, height: 36)
            Text("×\(event.quantity)")
                .font(.system(size: 17, weight: .heavy).italic())
                .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.40))
                .fixedSize()
        }
        .padding(.horizontal, 9).frame(height: 48)
        .background(LinearGradient(colors: [NanaPalette.violet.opacity(0.65), NanaPalette.deepSpace.opacity(0.75)], startPoint: .leading, endPoint: .trailing), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo gift: \(event.sender.displayName), \(event.item.title), quantity \(event.quantity)")
    }

    private func appendLine() {
        let participants = audience
        guard !participants.isEmpty else { return }
        let index = sequence + seed
        lines.append(ReplayLine(id: sequence, name: participants[index % participants.count].displayName, text: phrases[index % phrases.count]))
        lines = Array(lines.suffix(3))
        sequence += 1
    }

    private func showGift() {
        let index = seed + tick / 5
        let catalog = NanaGift.roomCatalog
        let participants = audience
        guard !catalog.isEmpty, !participants.isEmpty else { return }
        let sender = participants[(index + 1) % participants.count]
        gift = ReplayGift(id: tick, sender: sender, item: catalog[index % catalog.count], quantity: [1, 3, 5, 10][index % 4])
    }
}
