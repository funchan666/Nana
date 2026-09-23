import SwiftUI

/// Local presentation effects for bundled video and voice rooms. These events are never
/// persisted as messages, added to live membership, or sent to the coin ledger.
@MainActor
struct NanaRoomReplayActivityView: View {
    let room: NanaLiveRoom
    let recordedMessages: [NanaRoomChatMessage]
    let audience: [NanaReplayAudienceMember]
    let isActive: Bool
    var hidesGiftEffects = false
    var isVoiceRoom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lines: [ReplayLine] = []
    @State private var gift: ReplayGift?
    @State private var tick = 0
    @State private var sequence = 0

    private struct ReplayLine: Identifiable {
        let id: Int
        let senderID: String
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
        if isVoiceRoom { return voicePhrases }
        let common = ["Love the energy here!", "Sending a little good energy your way.", "That made me smile.", "Such a lovely moment."]
        switch room.category {
        case "Music": return ["This is going on my playlist.", "One more song, please!", "The rhythm is everything.", "Headphones on. I'm staying here."] + common
        case "Creative": return ["Where do you find your inspiration?", "That detail is so good.", "Love seeing the process.", "Keep creating. This is beautiful."] + common
        case "Late night": return ["Perfect company for a quiet night.", "The best conversations happen late.", "Taking a little break here.", "This feels like a cozy corner."] + common
        default: return ["Hello from my little corner!", "What's everyone up to today?", "Glad I found this room.", "Let's hear another story."] + common
        }
    }

    private var voicePhrases: [String] {
        switch room.id {
        case "room-aurora": return [
            "What was the best part of your day?", "A quiet chat was exactly what I needed.",
            "I'm making tea. Keep the stories coming.", "Little wins count too.",
            "That is such a comforting way to put it.", "No rush, we're listening."
        ]
        case "room-studio": return [
            "What are you working on this week?", "I'd start with the colors, then the details.",
            "I keep a notebook for ideas like that.", "Tell us how that first draft came together.",
            "A tiny sketch can become a whole project.", "That gave me an idea for tomorrow."
        ]
        case "room-lantern": return [
            "Can I join the next round of questions?", "Coffee or tea for everyone tonight?",
            "My answer changes every time I think about it.", "Let's give the next person a turn.",
            "That story deserves a second chapter.", "I came to listen and stayed for the conversation."
        ]
        case "room-midnight": return [
            "Can we put on something mellow next?", "That chord progression is lovely.",
            "What song always takes you back?", "The keys sound so warm with headphones.",
            "This belongs on a late-night playlist.", "A little groove makes the conversation better."
        ]
        case "room-city": return [
            "What's your favorite corner of the city?", "I found a tiny bakery on my walk today.",
            "Taking the long way home is underrated.", "Window seats and people-watching for me.",
            "Does anyone else collect little cafe spots?", "Tell us about your neighborhood."
        ]
        case "room-outdoors": return [
            "Forest trail or a walk by the water?", "I always pack an extra snack for a walk.",
            "The best part is stopping to enjoy the view.", "A little fresh air can reset the whole day.",
            "What's the next place you want to explore?", "Slow walks lead to the best stories."
        ]
        default: return [
            "Glad I found \(room.title).", "What got you into \(room.category.lowercased())?",
            "I'd love to hear everyone's take on that.", "Thanks for making space for this conversation.",
            "What's one thing you'd recommend to someone new?", "Take your time, we're listening."
        ]
        }
    }

    private var giftSequence: [Int] {
        guard isVoiceRoom else { return Array(NanaGift.roomCatalog.indices) }
        switch room.id {
        case "room-aurora": return [0, 4, 1]
        case "room-studio": return [1, 5, 7]
        case "room-lantern": return [2, 0, 5]
        case "room-midnight": return [6, 7, 4]
        case "room-city": return [3, 1, 0]
        case "room-outdoors": return [4, 0, 3]
        default: return [seed % 8, (seed + 3) % 8, (seed + 5) % 8]
        }
    }

    private var audienceIDs: Set<String> { Set(audience.map(\.id)) }
    private var visibleLines: [ReplayLine] { lines.filter { audienceIDs.contains($0.senderID) } }
    private var giftInterval: Int { isVoiceRoom ? 4 + seed % 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !isVoiceRoom {
                Text("Room activity")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            ZStack(alignment: .leading) {
                if let gift, audienceIDs.contains(gift.sender.id), !hidesGiftEffects {
                    giftBanner(gift)
                        .id(gift.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(height: hidesGiftEffects ? 0 : 50, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isVoiceRoom {
                Text("Keep it kind. Enjoy the room and respect each other.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            }
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
                ForEach(Array(visibleLines.suffix(recordedMessages.isEmpty ? 3 : 1))) { line in
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
        .onChange(of: audience.map(\.id)) { _, _ in
            lines.removeAll { !audienceIDs.contains($0.senderID) }
            if let current = gift, !audienceIDs.contains(current.sender.id) { gift = nil }
            if isActive, !audience.isEmpty {
                for _ in lines.count..<3 { appendLine() }
                if gift == nil { showGift() }
            }
        }
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
                    if tick.isMultiple(of: giftInterval) { showGift() }
                    else if tick % giftInterval == 3 { gift = nil }
                }
            }
        }
    }

    private func giftBanner(_ event: ReplayGift) -> some View {
        HStack(spacing: 7) {
            NanaAvatarView(title: event.sender.displayName, assetKey: event.sender.avatarAssetKey, size: 29)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.sender.displayName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(isVoiceRoom ? event.item.title : "\(event.item.title) · Preview")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
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
        let member = participants[index % participants.count]
        lines.append(ReplayLine(id: sequence, senderID: member.id, name: member.displayName, text: phrases[index % phrases.count]))
        lines = Array(lines.suffix(3))
        sequence += 1
    }

    private func showGift() {
        let index = seed + tick / giftInterval
        let catalog = NanaGift.roomCatalog
        let participants = audience
        let choices = giftSequence.filter { catalog.indices.contains($0) }
        guard !choices.isEmpty, !participants.isEmpty else { return }
        let sender = participants[(index + 1) % participants.count]
        let item = catalog[choices[index % choices.count]]
        let quantity = [1, 3, 5, 10][index % 4]
        gift = ReplayGift(id: tick, sender: sender, item: item, quantity: quantity)
        if isVoiceRoom {
            lines.append(ReplayLine(id: sequence, senderID: sender.id, name: sender.displayName,
                                    text: "Sent \(item.title) ×\(quantity)"))
            lines = Array(lines.suffix(3))
            sequence += 1
        }
    }
}
