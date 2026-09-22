import SwiftUI
import UIKit

struct NanaGiftConfirmationCard: View {
    let receipt: NanaRoomGiftReceipt
    let hostAvatar: String?
    let balance: Int
    let errorMessage: String?
    let cancel: () -> Void
    let send: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            header
            giftArtwork
            recipient
            priceSummary
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12))
                    .foregroundStyle(NanaPalette.softPink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(Color(red: 0.08, green: 0.055, blue: 0.12), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(NanaPalette.electricLilac.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 22, y: 10)
        .foregroundStyle(.white)
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, cancel)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Send a little joy").font(.system(size: 20, weight: .bold))
                Text("Make their moment brighter")
                    .font(.system(size: 12)).foregroundStyle(NanaPalette.mutedWhite)
            }
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: Circle())
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Cancel gift")
        }
    }

    private var giftArtwork: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                NanaAssetImage(assetKey: receipt.gift.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit)
                    .frame(width: 76, height: 76).padding(18)
                    .background(NanaPalette.violet.opacity(0.16), in: RoundedRectangle(cornerRadius: 24))
                Text("×\(receipt.quantity)")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(NanaPalette.violet, in: Capsule())
                    .offset(x: 8, y: 4)
            }
            Text(receipt.gift.title).font(.system(size: 17, weight: .semibold))
        }
    }

    private var recipient: some View {
        HStack(spacing: 7) {
            Text("To").foregroundStyle(NanaPalette.mutedWhite)
            NanaAvatarView(title: receipt.hostName, assetKey: hostAvatar, size: 25)
            Text(receipt.hostName).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var priceSummary: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Total").font(.system(size: 13))
                Spacer()
                if receipt.totalCoins > 0 {
                    NanaAssetImage(assetKey: "nana.voice.voice_asset_110", contentMode: .fit)
                        .frame(width: 18, height: 18)
                }
                Text(receipt.totalCoins == 0 ? "Free" : receipt.totalCoins.formatted())
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(receipt.totalCoins == 0 ? Color.mint : Color(red: 1, green: 0.82, blue: 0.39))
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack {
                Text("Balance after sending")
                Spacer(minLength: 4)
                Text("\(max(0, balance - receipt.totalCoins).formatted()) coins").monospacedDigit()
            }
            .font(.system(size: 11)).foregroundStyle(NanaPalette.mutedWhite)
        }
        .padding(14).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: cancel) {
                Text("Cancel").frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            Button(action: send) {
                HStack(spacing: 6) {
                    Text("Send gift")
                    Image(systemName: "paperplane.fill").font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(NanaPalette.violet, in: Capsule())
            }
        }
        .font(.system(size: 14, weight: .semibold)).buttonStyle(.plain)
    }
}

struct NanaSentRoomGiftBanner: View {
    let receipt: NanaRoomGiftReceipt
    let avatarData: Data?

    var body: some View {
        HStack(spacing: 9) {
            senderAvatar
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.senderName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("Sent \(receipt.gift.title)").font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
            NanaAssetImage(assetKey: receipt.gift.assetKey ?? "nana.voice.voice_asset_077", contentMode: .fit)
                .frame(width: 40, height: 40)
            Text("×\(receipt.quantity)").font(.system(size: 22, weight: .heavy).italic())
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.39)).fixedSize()
        }
        .padding(.horizontal, 12).frame(height: 60)
        .background(LinearGradient(colors: [NanaPalette.violet.opacity(0.9), NanaPalette.deepSpace.opacity(0.9)], startPoint: .leading, endPoint: .trailing), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
        .frame(maxWidth: 310)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(receipt.senderName) sent \(receipt.gift.title), quantity \(receipt.quantity), to \(receipt.hostName)")
        .allowsHitTesting(false)
    }

    private var senderAvatar: some View {
        Group {
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NanaAvatarView(title: receipt.senderName, assetKey: nil, size: 36)
            }
        }
        .frame(width: 36, height: 36).clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
    }
}
