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
    var coins: Int { baseCoins + bonusCoins }
}

private struct NanaPendingPurchase: Codable, Hashable {
    let transactionID: String
    let productID: String
    let ownerAccountID: String
    let receipt: String
    var orderCode: String?
}

private struct NanaCoinAccountRecord: Codable {
    var balance: Int
    var receivedWelcomeGift: Bool
    var processedTransactionIDs: Set<UInt64>
    var pendingPurchases: [String: NanaPendingPurchase]? = nil
    var pendingOrderCodes: [String: String]? = nil
    var roomGiftReceipts: [NanaRoomGiftReceipt]? = nil
    var purchaseAccountToken: UUID? = nil
}

private struct NanaCoinLedger: Codable {
    var accounts: [String: NanaCoinAccountRecord] = [:]
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
    @Published private(set) var purchasingAccountScope: String?
    var isPresentingPurchase: Bool {
        purchasingProductID != nil && accountScope != nil && accountScope == purchasingAccountScope
    }
    @Published var notice: AccountEntryNotice?

    private let keychainService = "com.nanalantern.harbortide.coins"
    private let keychainAccount = "ledger.v1"
    private var ledger = NanaCoinLedger()
    private var ledgerLoaded = false
    private var accountScope: String?
    private var transactionUpdatesTask: Task<Void, Never>?
    private let authentication: NanaAuthenticationBoundary

    init(authentication: NanaAuthenticationBoundary? = nil) {
        self.authentication = authentication ?? NanaAuthenticationBoundary()
    }

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
        startTransactionListener()
        guard let accountID else { return }

        do {
            try loadLedgerIfNeeded()
            if let record = ledger.accounts[accountID] {
                balance = record.balance
                roomGiftReceipts = record.roomGiftReceipts ?? []
            } else {
                ledger.accounts[accountID] = NanaCoinAccountRecord(balance: 1_200, receivedWelcomeGift: true, processedTransactionIDs: [])
                balance = 1_200
                try persistLedger()
            }
            Task { await retryPendingServerConfirmations(accountID: accountID) }
        } catch {
            notice = AccountEntryNotice(title: "Wallet unavailable", explanation: "Nana couldn't open your coin balance. Please try again.")
        }
    }

    private func retryPendingServerConfirmations(accountID: String) async {
        guard accountScope == accountID else { return }
        do {
            try loadLedgerIfNeeded()
            guard var record = ledger.accounts[accountID] else { return }
            var changed = false
            for pending in (record.pendingPurchases ?? [:]).values {
                guard let orderCode = pending.orderCode, !orderCode.isEmpty,
                      let pack = Self.packs.first(where: { $0.productID == pending.productID }) else { continue }
                do {
                    try await authentication.confirmPurchase(transactionID: pending.transactionID, receipt: pending.receipt, orderCode: orderCode)
                    record.pendingPurchases?.removeValue(forKey: pending.transactionID)
                    record.pendingOrderCodes?.removeValue(forKey: pending.productID)
                    if let id = UInt64(pending.transactionID) { record.processedTransactionIDs.insert(id) }
                    record.balance += pack.coins
                    changed = true
                } catch { }
            }
            guard changed else { return }
            var updated = ledger
            updated.accounts[accountID] = record
            try persistLedger(updated)
            ledger = updated
            balance = record.balance
        } catch { }
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
        notice = nil
    }

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

    func loadProducts() async {
        guard !isLoadingProducts, let scope = accountScope else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.packs.map(\.productID))
            guard accountScope == scope else { return }
            products = loaded.filter { $0.type == .consumable }
        } catch {
        }
    }

    func priceLabel(for pack: NanaCoinPack) -> String {
        products.first(where: { $0.id == pack.productID })?.displayPrice ?? "View price"
    }

    func purchase(pack: NanaCoinPack, orderCode: String? = nil) async {
        guard purchasingProductID == nil else { return }
        guard let purchasingAccount = accountScope else {
            notice = AccountEntryNotice(title: "Sign in required", explanation: "Sign in before adding coins to your balance.")
            return
        }
        purchasingAccountScope = purchasingAccount
        purchasingProductID = pack.productID
        defer { purchasingProductID = nil; purchasingAccountScope = nil }
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
            if let orderCode, !orderCode.isEmpty {
                var pendingOrderCodes = record.pendingOrderCodes ?? [:]
                pendingOrderCodes[pack.productID] = orderCode
                record.pendingOrderCodes = pendingOrderCodes
            }
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

    func canAfford(_ amount: Int, action: String) -> Bool {
        guard balance >= amount else {
            notice = AccountEntryNotice(title: "More coins needed", explanation: "\(action) needs \(amount) coins. Open Wallet to add more.")
            return false
        }
        return true
    }

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
            guard !(ledger.accounts.values.contains { $0.processedTransactionIDs.contains(transaction.id) }),
                  !(ledger.removedAccountTransactionIDs ?? []).contains(transaction.id) else {
                await transaction.finish()
                return
            }
            let owner: String?
            if let token = transaction.appAccountToken {
                owner = ledger.accounts.first(where: { $0.value.purchaseAccountToken == token })?.key
            } else { owner = purchasingAccount }
            guard let owner, var record = ledger.accounts[owner] else {
                notice = AccountEntryNotice(title: "Purchase needs account verification", explanation: "This purchase could not be linked to its original Nana account. No coins were assigned to the current account.")
                return
            }
            guard let receiptURL = Bundle.main.appStoreReceiptURL,
                  let receiptData = try? Data(contentsOf: receiptURL), !receiptData.isEmpty else {
                notice = AccountEntryNotice(title: "Purchase awaiting receipt", explanation: "Apple confirmed the purchase. Nana will verify it when the receipt is available.")
                return
            }
            let transactionID = String(transaction.id)
            let existing = record.pendingPurchases?[transactionID]
            let pending = NanaPendingPurchase(transactionID: transactionID, productID: expectedPack.productID, ownerAccountID: owner, receipt: existing?.receipt ?? receiptData.base64EncodedString(), orderCode: existing?.orderCode ?? record.pendingOrderCodes?[expectedPack.productID])
            var pendingPurchases = record.pendingPurchases ?? [:]
            pendingPurchases[transactionID] = pending
            record.pendingPurchases = pendingPurchases
            var updatedLedger = ledger
            updatedLedger.accounts[owner] = record
            try persistLedger(updatedLedger)
            ledger = updatedLedger
            guard let orderCode = pending.orderCode, !orderCode.isEmpty else {
                notice = AccountEntryNotice(title: "Purchase awaiting confirmation", explanation: "Apple confirmed the purchase. Nana will finish it after the order is confirmed.")
                return
            }
            try await authentication.confirmPurchase(transactionID: pending.transactionID, receipt: pending.receipt, orderCode: orderCode)
            guard var confirmedRecord = ledger.accounts[owner], confirmedRecord.pendingPurchases?[transactionID] != nil else { return }
            confirmedRecord.pendingPurchases?.removeValue(forKey: transactionID)
            confirmedRecord.pendingOrderCodes?.removeValue(forKey: expectedPack.productID)
            confirmedRecord.processedTransactionIDs.insert(transaction.id)
            confirmedRecord.balance += expectedPack.coins
            var confirmedLedger = ledger
            confirmedLedger.accounts[owner] = confirmedRecord
            try persistLedger(confirmedLedger)
            ledger = confirmedLedger
            if accountScope == owner { balance = confirmedRecord.balance }
            await transaction.finish()
        } catch {
            notice = AccountEntryNotice(title: "Purchase awaiting confirmation", explanation: "Apple confirmed the purchase, but Nana could not finish server confirmation. Please keep the app open and try again.")
        }
    }

    private func verifiedTransaction(from verification: VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        guard case .verified(let transaction) = verification else { return nil }
        #if !DEBUG
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

struct NanaPaymentOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Processing purchase…").font(.headline)
                Text("Keep Nana open while Apple and the account service confirm this order.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(28)
            .frame(maxWidth: 320)
            .background(Color(red: 0.12, green: 0.08, blue: 0.18), in: RoundedRectangle(cornerRadius: 22))
        }
        .allowsHitTesting(true)
    }
}
