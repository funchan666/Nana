import Foundation
import Security
import StoreKit
import SwiftUI
import Network

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
    var identity: UUID? = nil
    var accounts: [String: NanaCoinAccountRecord] = [:]
    var removedAccountTransactionIDs: Set<UInt64>? = nil
}

@MainActor
final class NanaCoinStore: ObservableObject {
    static let shared = NanaCoinStore()
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
    private let purchaseLedger = NanaPurchaseLedger()
    private let pathMonitor = NWPathMonitor()
    private var wasOnline = false
    private var legacyMigrationComplete = false
    private var purchaseSessionRevision = UUID()
    private var recoveryScan: Task<Void, Never>?
    private var bufferedTransactions: [String: StoreKit.Transaction] = [:]
    private var livePurchaseContexts: [String: UUID] = [:]
    private var processing: [String: Task<Bool, Never>] = [:]
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private var retryAttempts: [String: Int] = [:]

    private init(authentication: NanaAuthenticationBoundary? = nil) {
        self.authentication = authentication ?? NanaAuthenticationBoundary()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func beginSession(accountID: String?) {
        purchaseSessionRevision = UUID()
        accountScope = accountID
        balance = 0
        roomGiftReceipts = []
        products = []
        notice = nil
        start()
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
            wakeRecovery()
        } catch {
            notice = AccountEntryNotice(title: "Wallet unavailable", explanation: "Nana couldn't open your coin balance. Please try again.")
        }
    }

    func deleteLocalAccountData(accountID: String) throws {
        guard accountScope == accountID, purchasingProductID == nil else { throw NanaRoomGiftError.accountChanged }
        try prepareRecoveryLedger()
        guard legacyMigrationComplete, purchaseLedger.unreadableAccounts.isEmpty else { throw NanaCoinPurchaseError.storageUnavailable }
        guard !purchaseLedger.orders.values.contains(where: {
            $0.binding.owner == accountID && !$0.delivered && $0.state != .unpaid
        }) else { throw NanaCoinPurchaseError.storageUnavailable }
        var updated = ledger
        let removed = updated.accounts.removeValue(forKey: accountID)
        updated.removedAccountTransactionIDs = (updated.removedAccountTransactionIDs ?? []).union(removed?.processedTransactionIDs ?? [])
        try persistLedger(updated)
        ledger = updated
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

    func purchase(pack: NanaCoinPack) async {
        guard Self.packs.contains(pack) else { return }
        await purchase(productID: pack.productID, source: .hostLocal, coins: pack.coins, confirmation: nil)
    }

    func purchaseFromRealtime(productID: String, orderCode: String, messageID: String, requestID: UUID) async {
        guard !productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !orderCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !messageID.isEmpty else { return }
        let confirmation = NanaPurchaseConfirmation.current(orderCode: orderCode, messageID: messageID, requestID: requestID)
        await purchase(productID: productID, source: .ablyServer, coins: nil, confirmation: confirmation)
    }

    private func purchase(productID: String, source: NanaPurchaseSource, coins: Int?, confirmation: NanaPurchaseConfirmation?) async {
        guard purchasingProductID == nil, let owner = accountScope else { return }
        let revision = purchaseSessionRevision
        purchasingAccountScope = owner
        purchasingProductID = productID
        defer { purchasingProductID = nil; purchasingAccountScope = nil }
        var orderID: UUID?
        do {
            try prepareRecoveryLedger()
            if let confirmation {
                guard legacyMigrationComplete, purchaseLedger.unreadableAccounts.isEmpty else { throw NanaCoinPurchaseError.storageUnavailable }
                if let previous = purchaseLedger.orders.values.first(where: {
                    $0.binding.confirmation.map {
                        $0.origin == confirmation.origin && ($0.orderCode == confirmation.orderCode || $0.messageID == confirmation.messageID)
                    } ?? ($0.binding.legacyOrderCode == confirmation.orderCode)
                }) {
                    wakeRecovery()
                    showPurchaseNotice(owner: owner, revision: revision, pending: !previous.delivered)
                    return
                }
            }
            guard AppStore.canMakePayments else { throw NanaCoinPurchaseError.productNotFound }
            let product = try await product(for: productID)
            guard accountScope == owner, purchaseSessionRevision == revision else { return }
            guard product.type == .consumable else { throw NanaCoinPurchaseError.productNotFound }
            try loadLedgerIfNeeded()
            guard var account = ledger.accounts[owner], let walletID = ledger.identity else {
                throw NanaCoinPurchaseError.storageUnavailable
            }
            let token = account.purchaseAccountToken ?? UUID()
            guard !purchaseLedger.orders.values.contains(where: {
                $0.binding.owner == owner && $0.binding.productID == productID && $0.transactionID == nil &&
                ($0.state == .awaitingApple || $0.state == .needsReview)
            }) else {
                showPurchaseNotice(owner: owner, revision: revision, pending: true)
                return
            }
            account.purchaseAccountToken = token
            var updated = ledger
            updated.accounts[owner] = account
            try persistLedger(updated)
            ledger = updated
            let id = UUID()
            let binding = NanaPurchaseBinding(id: id, source: source, productID: productID, productType: "consumable",
                owner: owner, appAccountToken: token, bundleID: Bundle.main.bundleIdentifier ?? "",
                version: NanaAServiceConfiguration.clientVersion, deviceID: try NanaDeviceIdentity().value(),
                walletID: walletID, localCoins: coins, confirmation: confirmation, legacyKey: nil, legacyOrderCode: nil)
            guard !binding.bundleID.isEmpty else { throw NanaCoinPurchaseError.storageUnavailable }
            let order = NanaPurchaseOrder(schemaVersion: 1, binding: binding, state: .awaitingApple, retryCount: 0)
            try purchaseLedger.save(order)
            orderID = id
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let verification):
                let finished = await receive(verification, purchaseContext: id)
                if !finished { showPurchaseNotice(owner: owner, revision: revision, pending: true) }
            case .pending:
                showPurchaseNotice(owner: owner, revision: revision, pending: true)
            case .userCancelled:
                markUnpaid(id)
            @unknown default:
                showPurchaseNotice(owner: owner, revision: revision, pending: true)
            }
        } catch {
            if let orderID, var order = purchaseLedger.orders[orderID], !order.delivered {
                order.lastFailure = "purchaseOutcomeUnresolved"
                _ = try? purchaseLedger.save(order)
            }
            guard accountScope == owner, purchaseSessionRevision == revision else { return }
            notice = AccountEntryNotice(title: "Purchase unavailable", explanation: "Nana couldn't complete this purchase. Any confirmed Apple payment is kept for recovery; please do not buy it again.")
        }
    }

    private func showPurchaseNotice(owner: String, revision: UUID, pending: Bool) {
        guard pending, accountScope == owner, purchaseSessionRevision == revision else { return }
        notice = AccountEntryNotice(title: "Purchase pending", explanation: "This purchase is awaiting confirmation. Please do not purchase it again; Nana will retry when its original order and receipt are available.")
    }

    private func markUnpaid(_ id: UUID) {
        guard var order = purchaseLedger.orders[id], order.state == .awaitingApple, order.transactionID == nil else { return }
        order.state = .unpaid
        _ = try? purchaseLedger.save(order)
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

    func start() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            for await verification in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                Task { @MainActor [weak self] in _ = await self?.receive(verification) }
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if online && !self.wasOnline { self.wakeRecovery() }
                self.wasOnline = online
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.nanalantern.purchase-recovery"))
        wakeRecovery()
    }

    func wakeRecovery() {
        guard recoveryScan == nil else { return }
        retryAttempts.removeAll()
        recoveryScan = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recoveryScan = nil }
            do { try self.prepareRecoveryLedger() } catch { return }
            for (key, transaction) in self.bufferedTransactions {
                Task { @MainActor [weak self] in
                    _ = await self?.receive(.verified(transaction), purchaseContext: self?.livePurchaseContexts[key])
                }
            }
            for await verification in StoreKit.Transaction.unfinished {
                guard !Task.isCancelled else { return }
                guard let transaction = self.verifiedTransaction(from: verification) else { continue }
                let key = self.transactionKey(transaction)
                self.bufferedTransactions[key] = transaction
                Task { @MainActor [weak self] in
                    _ = await self?.receive(.verified(transaction), purchaseContext: self?.livePurchaseContexts[key])
                }
            }
        }
    }

    private func prepareRecoveryLedger() throws {
        try purchaseLedger.reload()
        legacyMigrationComplete = false
        do {
            try loadLedgerIfNeeded()
            if ledger.identity == nil {
                var updated = ledger
                updated.identity = UUID()
                try persistLedger(updated)
                ledger = updated
            }
            try migrateLegacyOrders()
            legacyMigrationComplete = true
        } catch {
            guard purchaseLedger.ready else { throw error }
        }
    }

    private func migrateLegacyOrders() throws {
        var migrationFailed = false
        for (owner, account) in ledger.accounts {
            for pending in (account.pendingPurchases ?? [:]).values {
                let key = owner + ":transaction:" + pending.transactionID
                if purchaseLedger.orders.values.contains(where: { $0.binding.legacyKey == key }) { continue }
                let binding = NanaPurchaseBinding(id: UUID(), source: .legacyUnknown, productID: pending.productID,
                    productType: "consumable", owner: owner, appAccountToken: account.purchaseAccountToken,
                    bundleID: Bundle.main.bundleIdentifier ?? "", version: nil, deviceID: nil, walletID: ledger.identity,
                    localCoins: nil, confirmation: nil, legacyKey: key, legacyOrderCode: pending.orderCode)
                let order = NanaPurchaseOrder(schemaVersion: 1, binding: binding, transactionID: pending.transactionID,
                    state: .needsReview, retryCount: 0, lastFailure: "legacyOriginAndBindingUnproven")
                do { try purchaseLedger.save(order) } catch { migrationFailed = true }
            }
            for (productID, code) in account.pendingOrderCodes ?? [:] {
                let key = owner + ":product:" + productID + ":" + code
                if purchaseLedger.orders.values.contains(where: { $0.binding.legacyKey == key }) { continue }
                let binding = NanaPurchaseBinding(id: UUID(), source: .legacyUnknown, productID: productID,
                    productType: "consumable", owner: owner, appAccountToken: account.purchaseAccountToken,
                    bundleID: Bundle.main.bundleIdentifier ?? "", version: nil, deviceID: nil, walletID: ledger.identity,
                    localCoins: nil, confirmation: nil, legacyKey: key, legacyOrderCode: code)
                do {
                    try purchaseLedger.save(NanaPurchaseOrder(schemaVersion: 1, binding: binding,
                        state: .needsReview, retryCount: 0, lastFailure: "legacyProductOnlyAssociation"))
                } catch { migrationFailed = true }
            }
        }
        if migrationFailed { throw NanaCoinPurchaseError.storageUnavailable }
    }

    private func environment(_ transaction: StoreKit.Transaction) -> String {
        if transaction.environment == .production { return "production" }
        if transaction.environment == .sandbox { return "sandbox" }
        return "xcode"
    }

    private func transactionKey(_ transaction: StoreKit.Transaction) -> String {
        transaction.appBundleID + ":" + environment(transaction) + ":" + String(transaction.id)
    }

    private func receive(_ verification: VerificationResult<StoreKit.Transaction>, purchaseContext: UUID? = nil) async -> Bool {
        guard let transaction = verifiedTransaction(from: verification), transaction.productType == .consumable,
              transaction.revocationDate == nil, transaction.appBundleID == Bundle.main.bundleIdentifier else { return false }
        let key = transactionKey(transaction)
        bufferedTransactions[key] = transaction
        if let purchaseContext {
            guard livePurchaseContexts[key] == nil || livePurchaseContexts[key] == purchaseContext else { return false }
            livePurchaseContexts[key] = purchaseContext
        }
        do {
            try prepareRecoveryLedger()
            let matches = purchaseLedger.orders.values.filter {
                $0.transactionID == String(transaction.id) && ($0.environment == nil || $0.environment == environment(transaction))
            }
            if matches.isEmpty, let purchaseContext, var order = purchaseLedger.orders[purchaseContext] {
                guard order.transactionID == nil, order.binding.productID == transaction.productID,
                      order.binding.appAccountToken == transaction.appAccountToken,
                      order.binding.bundleID == transaction.appBundleID else { return false }
                order.transactionID = String(transaction.id)
                order.environment = environment(transaction)
                order.state = .paid
                try purchaseLedger.save(order)
            } else if let purchaseContext, matches.first?.binding.id != purchaseContext {
                livePurchaseContexts[key] = nil
                if var refused = purchaseLedger.orders[purchaseContext], refused.transactionID == nil {
                    refused.state = .needsReview
                    refused.lastFailure = "transactionBelongsToAnotherOrder"
                    _ = try? purchaseLedger.save(refused)
                }
                schedule(transaction, key: key)
                return false
            }
            guard let task = schedule(transaction, key: key) else { return false }
            return await task.value
        } catch { return false }
    }

    @discardableResult
    private func schedule(_ transaction: StoreKit.Transaction, key: String) -> Task<Bool, Never>? {
        if let task = processing[key] { return task }
        guard purchaseLedger.ready,
              purchaseLedger.orders.values.contains(where: { $0.transactionID == String(transaction.id) }) else { return nil }
        retryTasks.removeValue(forKey: key)?.cancel()
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let completed = await self.process(transaction)
            self.processing[key] = nil
            if completed {
                self.bufferedTransactions[key] = nil
                self.livePurchaseContexts[key] = nil
                self.retryAttempts[key] = nil
            } else {
                self.scheduleRetry(transaction, key: key)
            }
            return completed
        }
        processing[key] = task
        return task
    }

    private func process(_ transaction: StoreKit.Transaction) async -> Bool {
        guard transaction.productType == .consumable, transaction.revocationDate == nil,
              transaction.appBundleID == Bundle.main.bundleIdentifier else { return false }
        do {
            let matches = purchaseLedger.orders.values.filter {
                $0.transactionID == String(transaction.id) && ($0.environment == nil || $0.environment == environment(transaction))
            }
            guard matches.count == 1, var order = matches.first,
                  order.binding.source != .legacyUnknown, order.state != .needsReview,
                  order.binding.productID == transaction.productID,
                  order.binding.appAccountToken == transaction.appAccountToken,
                  order.binding.bundleID == transaction.appBundleID else { return false }
            if order.state == .finished {
                await transaction.finish()
                return true
            }
            if !order.delivered {
                switch order.binding.source {
                case .hostLocal:
                    try loadLedgerIfNeeded()
                    guard ledger.identity == order.binding.walletID,
                          var record = ledger.accounts[order.binding.owner], let coins = order.binding.localCoins, coins > 0 else {
                        order.state = .needsReview
                        order.lastFailure = "originalWalletUnavailable"
                        try purchaseLedger.save(order)
                        return false
                    }
                    if !record.processedTransactionIDs.contains(transaction.id) {
                        order.state = .deliveringLocal
                        try purchaseLedger.save(order)
                        record.balance += coins
                        record.processedTransactionIDs.insert(transaction.id)
                        var updated = ledger
                        updated.accounts[order.binding.owner] = record
                        try persistLedger(updated)
                        ledger = updated
                        if accountScope == order.binding.owner { balance = record.balance }
                    }
                    order.state = .localDelivered
                    order = try purchaseLedger.save(order)
                case .ablyServer:
                    guard let confirmation = order.binding.confirmation, let version = order.binding.version,
                          let deviceID = order.binding.deviceID, let transactionID = order.transactionID else { return false }
                    guard let receiptURL = Bundle.main.appStoreReceiptURL,
                          let receipt = try? Data(contentsOf: receiptURL), !receipt.isEmpty else { return false }
                    try await authentication.confirmPurchase(transactionID: transactionID, receipt: receipt.base64EncodedString(),
                        confirmation: confirmation, version: version, deviceID: deviceID)
                    guard let current = purchaseLedger.orders[order.binding.id], current.binding == order.binding else { return false }
                    order = current
                    order.state = .serverConfirmed
                    order = try purchaseLedger.save(order)
                case .legacyUnknown:
                    return false
                }
            }
            guard order.delivered else { return false }
            await transaction.finish()
            order.state = .finished
            try purchaseLedger.save(order)
            return true
        } catch { return false }
    }

    private func scheduleRetry(_ transaction: StoreKit.Transaction, key: String) {
        let attempts = retryAttempts[key, default: 0]
        guard attempts < 3, let order = purchaseLedger.orders.values.first(where: {
            $0.transactionID == String(transaction.id) && $0.binding.source != .legacyUnknown && $0.state != .needsReview
        }) else { return }
        retryAttempts[key] = attempts + 1
        var pending = order
        pending.retryCount += 1
        pending.lastFailure = "deliveryPending"
        _ = try? purchaseLedger.save(pending)
        retryTasks[key] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds([2, 8, 30][attempts])) } catch { return }
            guard let self else { return }
            self.retryTasks[key] = nil
            do { try self.prepareRecoveryLedger() } catch { return }
            self.schedule(transaction, key: key)
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
        guard status == errSecSuccess else {
            ledgerLoaded = false
            throw NanaCoinPurchaseError.storageUnavailable
        }
        var readback = keychainQuery
        readback[kSecReturnData as String] = true
        readback[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(readback as CFDictionary, &result) == errSecSuccess,
              result as? Data == data else {
            ledgerLoaded = false
            throw NanaCoinPurchaseError.storageUnavailable
        }
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

enum NanaCoinPurchaseError: Error {
    case productNotFound
    case storageUnavailable
}

struct NanaPaymentOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Processing purchase…").font(.headline)
                Text("Keep Nana open while this purchase is being completed.")
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
