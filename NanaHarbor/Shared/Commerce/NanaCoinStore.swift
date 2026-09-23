import Foundation
import Security
import StoreKit
import SwiftUI

struct NanaCoinPack: Identifiable, Hashable {
    let productID: String
    let baseCoins: Int
    let bonusPercent: Int
    let fallbackPrice: String

    var id: String { productID }
    var bonusCoins: Int { baseCoins * bonusPercent / 100 }
    /// The same total powers the storefront and verified purchase credit.
    var coins: Int { baseCoins + bonusCoins }
}

struct NanaWelcomeGift {
    let amount: Int
    let title: String
    let detail: String
}

private struct NanaCoinAccountRecord: Codable {
    var balance: Int
    var receivedWelcomeGift: Bool
    var processedTransactionIDs: Set<UInt64>
    // Optional for compatibility with previously saved account ledgers.
    var roomGiftReceipts: [NanaRoomGiftReceipt]? = nil
    var purchaseAccountToken: UUID? = nil
}

private struct NanaCoinLedger: Codable {
    var accounts: [String: NanaCoinAccountRecord] = [:]
    // Unlinked transaction IDs prevent completed purchases being credited again
    // after local account removal. No profile or account identifier is retained.
    var removedAccountTransactionIDs: Set<UInt64>? = nil
}

@MainActor
final class NanaCoinStore: ObservableObject {
    static let packs = [
        NanaCoinPack(productID: "xtgkjmjhjxcvxgr", baseCoins: 500, bonusPercent: 20, fallbackPrice: "$0.99"),
        NanaCoinPack(productID: "zezqgkvbircdido", baseCoins: 1_000, bonusPercent: 30, fallbackPrice: "$1.99"),
        NanaCoinPack(productID: "qvntkzplmrxhcad", baseCoins: 1_500, bonusPercent: 35, fallbackPrice: "$2.99"),
        NanaCoinPack(productID: "npftelsnomirowvr", baseCoins: 2_500, bonusPercent: 40, fallbackPrice: "$4.99"),
        NanaCoinPack(productID: "rvkwjwglymgcdhk", baseCoins: 5_000, bonusPercent: 50, fallbackPrice: "$9.99"),
        NanaCoinPack(productID: "efmgfwjfueyseizi", baseCoins: 10_000, bonusPercent: 60, fallbackPrice: "$19.99"),
        NanaCoinPack(productID: "bhswqjfvndkztre", baseCoins: 15_000, bonusPercent: 65, fallbackPrice: "$29.99"),
        NanaCoinPack(productID: "dgedfppvsxndaou", baseCoins: 25_000, bonusPercent: 70, fallbackPrice: "$49.99"),
        NanaCoinPack(productID: "kcrboklodxeabcdx", baseCoins: 50_000, bonusPercent: 80, fallbackPrice: "$99.99")
    ]

    @Published private(set) var balance = 0
    @Published private(set) var roomGiftReceipts: [NanaRoomGiftReceipt] = []
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchasingProductID: String?
    @Published var notice: AccountEntryNotice?
    @Published private(set) var welcomeGift: NanaWelcomeGift?

    private let keychainService = "com.nanalantern.harbortide.coins"
    private let keychainAccount = "ledger.v1"
    private var ledger = NanaCoinLedger()
    private var ledgerLoaded = false
    private var accountScope: String?
    private var transactionUpdatesTask: Task<Void, Never>?

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func beginSession(accountID: String?) {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
        accountScope = accountID
        balance = 0
        roomGiftReceipts = []
        products = []
        notice = nil
        welcomeGift = nil
        guard let accountID else { return }

        do {
            try loadLedgerIfNeeded()
            if let record = ledger.accounts[accountID] {
                balance = record.balance
                roomGiftReceipts = record.roomGiftReceipts ?? []
            } else {
                let gift = NanaWelcomeGift(amount: 1_200, title: "Your first spark.", detail: "A little gift to light up your first day.")
                ledger.accounts[accountID] = NanaCoinAccountRecord(balance: gift.amount, receivedWelcomeGift: true, processedTransactionIDs: [])
                balance = gift.amount
                welcomeGift = gift
                try persistLedger()
            }
            startTransactionListener()
        } catch {
            notice = AccountEntryNotice(title: "Wallet unavailable", explanation: "Nana couldn't open your coin balance. Please try again.")
        }
    }

    func dismissWelcomeGift() {
        welcomeGift = nil
    }

    func deleteLocalAccountData(accountID: String) throws {
        guard accountScope == accountID, purchasingProductID == nil else { throw NanaRoomGiftError.accountChanged }
        try loadLedgerIfNeeded()
        var updated = ledger
        let removed = updated.accounts.removeValue(forKey: accountID)
        updated.removedAccountTransactionIDs = (updated.removedAccountTransactionIDs ?? []).union(removed?.processedTransactionIDs ?? [])
        try persistLedger(updated)
        ledger = updated
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
        balance = 0
        roomGiftReceipts = []
        welcomeGift = nil
        notice = nil
    }

    /// Seed only an account with no local record. Purchases and local spending are never overwritten by a refresh.
    func hydrateRemoteBalance(_ remoteBalance: Int) {
        guard let accountScope, remoteBalance >= 0 else { return }
        do {
            try loadLedgerIfNeeded()
            guard ledger.accounts[accountScope] == nil else { return }
            ledger.accounts[accountScope] = NanaCoinAccountRecord(balance: remoteBalance, receivedWelcomeGift: false, processedTransactionIDs: [])
            balance = remoteBalance
            try persistLedger()
        } catch {
            notice = AccountEntryNotice(title: "Wallet unavailable", explanation: "Nana couldn't save the current coin balance.")
        }
    }

    /// Prices come from Apple's current storefront, never the reference USD catalog.
    func loadProducts() async {
        guard !isLoadingProducts, let scope = accountScope else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.packs.map(\.productID))
            guard accountScope == scope else { return }
            products = loaded.filter { $0.type == .consumable }
        } catch {
            // Each purchase button can retry product loading on demand.
        }
    }

    func priceLabel(for pack: NanaCoinPack) -> String {
        products.first(where: { $0.id == pack.productID })?.displayPrice ?? "View price"
    }

    func purchase(pack: NanaCoinPack) async {
        guard purchasingProductID == nil else { return }
        guard let purchasingAccount = accountScope else {
            notice = AccountEntryNotice(title: "Sign in required", explanation: "Sign in before adding coins to your balance.")
            return
        }
        purchasingProductID = pack.productID
        defer { purchasingProductID = nil }
        do {
            let product = try await product(for: pack.productID)
            guard accountScope == purchasingAccount else { return }
            guard product.type == .consumable else {
                notice = AccountEntryNotice(title: "Product unavailable", explanation: "This coin pack is not configured as a consumable product.")
                return
            }
            try loadLedgerIfNeeded()
            guard var record = ledger.accounts[purchasingAccount] else { return }
            let token = record.purchaseAccountToken ?? UUID()
            record.purchaseAccountToken = token
            var updated = ledger
            updated.accounts[purchasingAccount] = record
            try persistLedger(updated)
            ledger = updated
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let verification):
                await apply(verification, expectedPack: pack, purchasingAccount: purchasingAccount)
            case .pending:
                notice = AccountEntryNotice(title: "Purchase pending", explanation: "Apple is still confirming this purchase. Your balance will update after confirmation.")
            case .userCancelled:
                break
            @unknown default:
                notice = AccountEntryNotice(title: "Purchase unavailable", explanation: "Apple couldn't start this purchase. Please try again.")
            }
        } catch {
            notice = AccountEntryNotice(title: "Purchase unavailable", explanation: "Apple couldn't load this coin pack. Please try again.")
        }
    }

    func dismissNotice() {
        notice = nil
    }

    /// Read-only affordability check. Purchases still require verified StoreKit transactions.
    func canAfford(_ amount: Int, action: String) -> Bool {
        guard balance >= amount else {
            notice = AccountEntryNotice(title: "More coins needed", explanation: "\(action) needs \(amount) coins. Open Wallet to add more.")
            return false
        }
        return true
    }

    /// Commits the debit and its receipt in one Keychain write. It represents a
    /// local gift interaction, not a server-confirmed delivery to another account.
    func sendRoomGift(_ receipt: NanaRoomGiftReceipt, accountID: String) throws {
        guard accountScope == accountID else { throw NanaRoomGiftError.accountChanged }
        try loadLedgerIfNeeded()
        guard var record = ledger.accounts[accountID] else { throw NanaRoomGiftError.accountChanged }
        if (record.roomGiftReceipts ?? []).contains(where: { $0.id == receipt.id }) { return }
        guard (1...99).contains(receipt.quantity),
              let catalogGift = NanaGift.roomCatalog.first(where: { $0.id == receipt.gift.id }),
              catalogGift == receipt.gift, receipt.totalCoins >= 0,
              !receipt.roomID.isEmpty else { throw NanaRoomGiftError.invalidGift }
        guard record.balance >= receipt.totalCoins else { throw NanaRoomGiftError.insufficientCoins }

        record.balance -= receipt.totalCoins
        record.roomGiftReceipts = (record.roomGiftReceipts ?? []) + [receipt]
        var updatedLedger = ledger
        updatedLedger.accounts[accountID] = record
        try persistLedger(updatedLedger)
        // Publish only after the debit AND history have been durably saved.
        ledger = updatedLedger
        balance = record.balance
        roomGiftReceipts = record.roomGiftReceipts ?? []
    }

    private func product(for productID: String) async throws -> Product {
        if let product = products.first(where: { $0.id == productID }) { return product }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        let loaded = try await Product.products(for: [productID])
        products = (products.filter { $0.id != productID } + loaded).sorted { left, right in
            let leftIndex = Self.packs.firstIndex { $0.productID == left.id } ?? .max
            let rightIndex = Self.packs.firstIndex { $0.productID == right.id } ?? .max
            return leftIndex < rightIndex
        }
        guard let product = products.first(where: { $0.id == productID }) else {
            throw NanaCoinPurchaseError.productNotFound
        }
        return product
    }

    private func startTransactionListener() {
        transactionUpdatesTask = Task { [weak self] in
            // Recover approved purchases interrupted by termination or a failed ledger write.
            for await verification in StoreKit.Transaction.unfinished {
                guard !Task.isCancelled else { return }
                await self?.handle(verification)
            }
            for await verification in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.handle(verification)
            }
        }
    }

    private func handle(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = verifiedTransaction(from: verification),
              let pack = Self.packs.first(where: { $0.productID == transaction.productID }) else { return }
        await apply(.verified(transaction), expectedPack: pack)
    }

    private func apply(_ verification: VerificationResult<StoreKit.Transaction>, expectedPack: NanaCoinPack,
                       purchasingAccount: String? = nil) async {
        guard let transaction = verifiedTransaction(from: verification),
              transaction.productID == expectedPack.productID,
              transaction.productType == .consumable, transaction.revocationDate == nil else {
            notice = AccountEntryNotice(title: "Purchase could not be verified", explanation: "No coins were added. Please try again or contact Apple Support.")
            return
        }
        do {
            try loadLedgerIfNeeded()
            guard !ledger.accounts.values.contains(where: { $0.processedTransactionIDs.contains(transaction.id) }),
                  !(ledger.removedAccountTransactionIDs ?? []).contains(transaction.id) else {
                await transaction.finish()
                return
            }
            // Delayed approvals remain attached to the purchasing account after a switch.
            let owner: String?
            if let token = transaction.appAccountToken {
                owner = ledger.accounts.first(where: { $0.value.purchaseAccountToken == token })?.key
            } else {
                owner = purchasingAccount
            }
            guard let owner, var record = ledger.accounts[owner] else {
                notice = AccountEntryNotice(title: "Purchase needs account verification",
                    explanation: "This purchase could not be linked to its original Nana account. No coins were assigned to the current account.")
                return
            }
            record.processedTransactionIDs.insert(transaction.id)
            record.balance += expectedPack.coins
            var updatedLedger = ledger
            updatedLedger.accounts[owner] = record
            try persistLedger(updatedLedger)
            ledger = updatedLedger
            if accountScope == owner { balance = record.balance }
            await transaction.finish()
        } catch {
            notice = AccountEntryNotice(title: "Balance not updated", explanation: "The purchase was verified, but Nana couldn't save the new balance. Please keep the app open and try again.")
        }
    }

    private func verifiedTransaction(from verification: VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        guard case .verified(let transaction) = verification else { return nil }
        #if !DEBUG
        // Apple sandbox transactions remain valid for TestFlight and App Review.
        // Xcode's local StoreKit test transactions are never fulfillment in Release.
        guard transaction.environment != .xcode else { return nil }
        #endif
        return transaction
    }

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: keychainAccount]
    }

    private func loadLedgerIfNeeded() throws {
        guard !ledgerLoaded else { return }
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            ledger = NanaCoinLedger()
        } else {
            guard status == errSecSuccess, let data = result as? Data,
                  let decoded = try? JSONDecoder().decode(NanaCoinLedger.self, from: data) else {
                throw NanaCoinPurchaseError.storageUnavailable
            }
            ledger = decoded
        }
        ledgerLoaded = true
    }

    private func persistLedger(_ updatedLedger: NanaCoinLedger? = nil) throws {
        let data = try JSONEncoder().encode(updatedLedger ?? ledger)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(keychainQuery as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = keychainQuery
            values.forEach { insertion[$0.key] = $0.value }
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NanaCoinPurchaseError.storageUnavailable }
    }
}

enum NanaRoomGiftError: LocalizedError {
    case accountChanged, invalidGift, insufficientCoins

    var errorDescription: String? {
        switch self {
        case .accountChanged: return "Please sign in again before sending a gift."
        case .invalidGift: return "Please select this gift again."
        case .insufficientCoins: return "Your balance is too low for this gift."
        }
    }
}

private enum NanaCoinPurchaseError: Error {
    case productNotFound
    case storageUnavailable
}

struct NanaWelcomeGiftOverlay: View {
    let gift: NanaWelcomeGift
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.76).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    card(artworkSize: geometry.size.height < 700 ? 180 : 220)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func card(artworkSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text("WELCOME TO NANA")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(NanaPalette.electricLilac)
                .padding(.top, 28)

            Image("NanaWelcomeCoin")
                .resizable()
                .scaledToFit()
                .frame(width: artworkSize, height: artworkSize)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.9)
                .offset(y: hasAppeared || reduceMotion ? 0 : 10)
                .accessibilityHidden(true)

            Text(gift.title)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(NanaPalette.warmWhite)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 4) {
                Text("+\(gift.amount.formatted())")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.56))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("COINS ADDED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(NanaPalette.electricLilac)
            }
            .padding(.top, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(gift.amount.formatted()) coins added")

            Text(gift.detail)
                .font(.system(size: 14))
                .foregroundStyle(NanaPalette.mutedWhite)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Button(action: dismiss) {
                Text("Let's explore")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(NanaPrimaryButtonStyle(tint: NanaPalette.violet))
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 350)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.12, green: 0.055, blue: 0.22), NanaPalette.deepSpace],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [NanaPalette.electricLilac.opacity(0.45), NanaPalette.electricLilac.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.4), radius: 24, y: 16)
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 16)
    }
}
