import Foundation
import Security
import StoreKit
import SwiftUI
import Network
import UIKit
import OSLog

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
    var processedStoreTransactionIDs: Set<String>? = nil
}

private struct NanaCoinLedger: Codable {
    var identity: UUID? = nil
    var accounts: [String: NanaCoinAccountRecord] = [:]
    var removedAccountTransactionIDs: Set<UInt64>? = nil
    var removedStoreTransactionIDs: Set<String>? = nil
}

private enum NanaPurchaseBlock: String {
    case appleQueuePending, appleApprovalPending, deliveryPending, legacyPreorderUnresolved, submissionUnresolved, reviewRequired, previousUnpaid
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
    @Published private(set) var products: [SKProduct] = []
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
    private var paymentObserver: NanaPaymentQueueObserver?
    private let productRequests = NanaStoreKitRequests()
    private let receiptRequests = NanaStoreKitRequests()
    private let purchaseLog = Logger(subsystem: "com.nanalantern.harbortide", category: "Purchase")
    private var productRequestCount = 0
    private var interactiveAttempt: UUID?
    private var interactiveOrderID: UUID?
    private var interactiveRevision: UUID?
    private var interactionDeadline: Task<Void, Never>?
    private var receiptRefreshAttempts = Set<UUID>()
    private let authentication: NanaAuthenticationBoundary
    private let purchaseLedger = NanaPurchaseLedger()
    private let pathMonitor = NWPathMonitor()
    private var wasOnline = false
    private var legacyMigrationComplete = false
    private var purchaseSessionRevision = UUID()
    private var recoveryScan: Task<Void, Never>?
    private var bufferedTransactions: [String: SKPaymentTransaction] = [:]
    private var observedTransactions: [ObjectIdentifier: SKPaymentTransaction] = [:]
    private var transactionOrders: [ObjectIdentifier: UUID] = [:]
    private var processing: [String: Task<Bool, Never>] = [:]
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private var retryAttempts: [String: Int] = [:]

    private init(authentication: NanaAuthenticationBoundary? = nil) {
        self.authentication = authentication ?? NanaAuthenticationBoundary()
    }

    func beginSession(accountID: String?) {
        purchaseSessionRevision = UUID()
        productRequests.cancelAll()
        releaseInteraction()
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
        updated.removedStoreTransactionIDs = (updated.removedStoreTransactionIDs ?? []).union(removed?.processedStoreTransactionIDs ?? [])
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
        let revision = purchaseSessionRevision
        productRequestCount += 1
        isLoadingProducts = true
        defer { productRequestCount -= 1; isLoadingProducts = productRequestCount > 0 }
        do {
            let loaded = try await productRequests.products(identifiers: Set(Self.packs.map(\.productID)))
            guard accountScope == scope, purchaseSessionRevision == revision else { return }
            products = loaded.products.filter { $0.subscriptionPeriod == nil }
        } catch { }
    }

    func priceLabel(for pack: NanaCoinPack) -> String {
        guard let product = products.first(where: { $0.productIdentifier == pack.productID }) else { return "View price" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price) ?? "View price"
    }

    func purchase(pack: NanaCoinPack) async {
        guard Self.packs.contains(pack) else { return }
        await purchase(productID: pack.productID, source: .hostLocal, coins: pack.coins, confirmation: nil)
    }

    func purchaseFromRealtime(productID: String, orderCode: String, messageID: String, requestID: UUID, explicitMessageID: String? = nil) async {
        guard !productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !orderCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !messageID.isEmpty else { return }
        let confirmation = NanaPurchaseConfirmation.current(orderCode: orderCode, messageID: messageID,
            requestID: requestID, explicitMessageID: explicitMessageID.flatMap { $0.isEmpty ? nil : $0 })
        await purchase(productID: productID, source: .ablyServer, coins: nil, confirmation: confirmation)
    }

    private func purchase(productID: String, source: NanaPurchaseSource, coins: Int?, confirmation: NanaPurchaseConfirmation?) async {
        guard purchasingProductID == nil, let owner = accountScope else { return }
        let revision = purchaseSessionRevision
        let attempt = UUID()
        interactiveAttempt = attempt
        interactiveRevision = revision
        purchasingAccountScope = owner
        purchasingProductID = productID
        purchaseLog.notice("Purchase requested source=\(source.rawValue, privacy: .public) product=\(productID, privacy: .public)")
        var submitted = false
        defer { if !submitted && interactiveAttempt == attempt { releaseInteraction() } }
        var orderID: UUID?
        do {
            try prepareRecoveryLedger()
            receive(SKPaymentQueue.default().transactions + Array(observedTransactions.values) + Array(bufferedTransactions.values))
            if let confirmation {
                guard legacyMigrationComplete, purchaseLedger.unreadableAccounts.isEmpty else { throw NanaCoinPurchaseError.storageUnavailable }
                if let messageID = confirmation.explicitMessageID,
                   purchaseLedger.orders.values.contains(where: {
                       guard let previous = $0.binding.confirmation else { return false }
                       return previous.origin == confirmation.origin && previous.orderCode != confirmation.orderCode &&
                           (previous.explicitMessageID ?? previous.messageID) == messageID
                   }) {
                    purchaseLog.error("Purchase rejected reason=conflictingBusinessMessage")
                    throw NanaCoinPurchaseError.storageUnavailable
                }
                if let previous = purchaseLedger.orders.values.first(where: {
                    $0.binding.confirmation.map {
                        $0.origin == confirmation.origin && $0.orderCode == confirmation.orderCode
                    } ?? ($0.binding.legacyOrderCode == confirmation.orderCode)
                }) {
                    wakeRecovery()
                    purchaseLog.notice("Purchase blocked reason=existingBackendOrder state=\(previous.state.rawValue, privacy: .public)")
                    if !previous.delivered { showPurchaseBlock(block(for: previous), owner: owner, revision: revision) }
                    return
                }
            }
            guard SKPaymentQueue.canMakePayments() else { throw NanaCoinPurchaseError.paymentsRestricted }
            let product = try await product(for: productID)
            if let recoveryScan { await recoveryScan.value }
            guard accountScope == owner, purchaseSessionRevision == revision, interactiveAttempt == attempt,
                  !Task.isCancelled else { return }
            guard product.subscriptionPeriod == nil else { throw NanaCoinPurchaseError.unsupportedProduct }
            try prepareRecoveryLedger()
            try loadLedgerIfNeeded()
            guard var account = ledger.accounts[owner], let walletID = ledger.identity else {
                throw NanaCoinPurchaseError.storageUnavailable
            }
            let token = account.purchaseAccountToken ?? UUID()
            let id = UUID()
            let binding = NanaPurchaseBinding(id: id, source: source, productID: productID, productType: "consumable",
                owner: owner, appAccountToken: token, bundleID: Bundle.main.bundleIdentifier ?? "",
                version: NanaAServiceConfiguration.clientVersion, deviceID: try NanaDeviceIdentity().value(),
                walletID: walletID, localCoins: coins, confirmation: confirmation, legacyKey: nil, legacyOrderCode: nil,
                applicationUsername: id.uuidString)
            guard !binding.bundleID.isEmpty else { throw NanaCoinPurchaseError.storageUnavailable }
            try isolateBlockingLegacyPreorder(for: binding)
            if let block = purchaseBlock(for: binding) {
                showPurchaseBlock(block, owner: owner, revision: revision)
                return
            }
            account.purchaseAccountToken = token
            var updated = ledger
            updated.accounts[owner] = account
            try persistLedger(updated)
            ledger = updated
            guard SKPaymentQueue.canMakePayments() else { throw NanaCoinPurchaseError.paymentsRestricted }
            if let block = purchaseBlock(for: binding) {
                showPurchaseBlock(block, owner: owner, revision: revision)
                return
            }
            let order = NanaPurchaseOrder(schemaVersion: 1, binding: binding, state: .awaitingApple, retryCount: 0,
                submissionVersion: 1, submissionStage: "preparedForApple", observedAppleStates: [], quantity: 1)
            try purchaseLedger.save(order)
            orderID = id
            let payment = SKMutablePayment(product: product)
            payment.quantity = 1
            payment.applicationUsername = binding.applicationUsername
            interactiveOrderID = id
            start()
            submitted = true
            beginInteractionDeadline(attempt: attempt, orderID: id)
            SKPaymentQueue.default().add(payment)
        } catch {
            if let orderID, var order = purchaseLedger.orders[orderID], !order.delivered {
                order.lastFailure = "purchaseOutcomeUnresolved"
                _ = try? purchaseLedger.save(order)
            }
            guard accountScope == owner, purchaseSessionRevision == revision else { return }
            if error is CancellationError { return }
            let reason = purchaseFailureReason(error)
            purchaseLog.error("Purchase not submitted product=\(productID, privacy: .public) reason=\(reason, privacy: .public) code=\((error as NSError).code)")
            notice = AccountEntryNotice(title: "Purchase unavailable", explanation: purchaseFailureMessage(error))
        }
    }

    private func purchaseFailureReason(_ error: Error) -> String {
        if let error = error as? NanaCoinPurchaseError {
            switch error {
            case .productNotFound: return "product_missing"
            case .invalidProductIdentifier: return "product_rejected"
            case .paymentsRestricted: return "payments_restricted"
            case .unsupportedProduct: return "unsupported_product"
            case .storageUnavailable: return "storage_unavailable"
            }
        }
        if error is NanaStoreRequestError { return "product_request_timeout" }
        if (error as NSError).domain == NSURLErrorDomain { return "network_error" }
        if error is SKError { return "store_error" }
        return "purchase_preparation_failed"
    }

    private func purchaseFailureMessage(_ error: Error) -> String {
        switch purchaseFailureReason(error) {
        case "product_rejected", "product_missing":
            return "This recharge option is currently unavailable in the App Store. Please choose another option. No Apple payment was started."
        case "payments_restricted":
            return "In-app purchases are not allowed on this device. Check your purchase restrictions and try again."
        case "unsupported_product":
            return "This recharge option is configured incorrectly. Please choose another option. No Apple payment was started."
        case "product_request_timeout", "network_error":
            return "The App Store could not be reached in time. Check your connection and try again. No Apple payment was started."
        case "storage_unavailable":
            return "Nana couldn't safely save this purchase. Unlock your device and try again. No Apple payment was started."
        default:
            return "Nana couldn't prepare this purchase. Please try again. No Apple payment was started."
        }
    }

    private func showPurchaseNotice(owner: String, revision: UUID, pending: Bool) {
        guard pending, accountScope == owner, purchaseSessionRevision == revision else { return }
        let reason = interactiveOrderID.flatMap { purchaseLedger.orders[$0] }.map { block(for: $0) } ?? .reviewRequired
        showPurchaseBlock(reason, owner: owner, revision: revision)
    }

    private func block(for order: NanaPurchaseOrder) -> NanaPurchaseBlock {
        if order.state == .unpaid { return .previousUnpaid }
        if order.state == .needsReview || order.binding.source == .legacyUnknown { return .reviewRequired }
        if order.transactionID != nil { return .deliveryPending }
        if order.observedAppleStates?.contains("deferred") == true { return .appleApprovalPending }
        if order.isUnobservedLegacyPreorder { return .legacyPreorderUnresolved }
        return .submissionUnresolved
    }

    private func showPurchaseBlock(_ reason: NanaPurchaseBlock, owner: String, revision: UUID) {
        guard accountScope == owner, purchaseSessionRevision == revision else { return }
        purchaseLog.notice("Purchase blocked reason=\(reason.rawValue, privacy: .public)")
        switch reason {
        case .appleQueuePending:
            notice = AccountEntryNotice(title: "Waiting for Apple", explanation: "An earlier purchase is still being processed by Apple. Please wait for its result before trying this option again.")
        case .appleApprovalPending:
            notice = AccountEntryNotice(title: "Approval pending", explanation: "An earlier purchase is waiting for approval. Nana will continue when Apple provides the result.")
        case .deliveryPending:
            notice = AccountEntryNotice(title: "Purchase pending", explanation: "An earlier Apple transaction still needs verification or completion. Nana will continue processing the original order; please do not purchase it again.")
        case .legacyPreorderUnresolved, .reviewRequired:
            notice = AccountEntryNotice(title: "Earlier order needs review", explanation: "An earlier order record is preventing this purchase. Its payment status has not been confirmed, and this message does not mean you were charged. No new Apple payment was started.")
        case .submissionUnresolved:
            notice = AccountEntryNotice(title: "Purchase result unavailable", explanation: "An earlier payment request has no final Apple result. Its status must be checked before this option can be submitted again. This message does not confirm a charge.")
        case .previousUnpaid:
            notice = AccountEntryNotice(title: "Previous order ended", explanation: "Apple cancelled or declined this order. Start a new recharge to request a new order; this old order will not be submitted again.")
        }
    }

    private func markUnpaid(_ id: UUID) throws {
        guard var order = purchaseLedger.orders[id], order.state == .awaitingApple, order.transactionID == nil else { return }
        order.state = .unpaid
        try purchaseLedger.save(order)
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

    private func product(for productID: String) async throws -> SKProduct {
        if let product = products.first(where: { $0.productIdentifier == productID }) { return product }
        let revision = purchaseSessionRevision
        productRequestCount += 1
        isLoadingProducts = true
        defer { productRequestCount -= 1; isLoadingProducts = productRequestCount > 0 }
        let loaded = try await productRequests.products(identifiers: [productID])
        guard revision == purchaseSessionRevision else { throw CancellationError() }
        products = (products.filter { $0.productIdentifier != productID } + loaded.products).sorted { left, right in
            let leftIndex = Self.packs.firstIndex { $0.productID == left.productIdentifier } ?? .max
            let rightIndex = Self.packs.firstIndex { $0.productID == right.productIdentifier } ?? .max
            return leftIndex < rightIndex
        }
        if loaded.invalidProductIdentifiers.contains(productID) {
            throw NanaCoinPurchaseError.invalidProductIdentifier
        }
        guard let product = loaded.products.first(where: { $0.productIdentifier == productID }) else {
            throw NanaCoinPurchaseError.productNotFound
        }
        return product
    }

    func start() {
        guard paymentObserver == nil else { return }
        let observer = NanaPaymentQueueObserver(
            receive: { [weak self] transactions in self?.receive(transactions) },
            removed: { [weak self] transactions in self?.removeObservedTransactions(transactions) })
        paymentObserver = observer
        SKPaymentQueue.default().add(observer)
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
            self.receive(Array(self.observedTransactions.values) + Array(self.bufferedTransactions.values) + SKPaymentQueue.default().transactions)
        }
    }

    private func releaseInteraction(orderID: UUID? = nil, pending: Bool = false) {
        if let orderID, interactiveOrderID != orderID { return }
        interactionDeadline?.cancel()
        interactionDeadline = nil
        if pending, let owner = purchasingAccountScope, let revision = interactiveRevision {
            showPurchaseNotice(owner: owner, revision: revision, pending: true)
        }
        purchasingProductID = nil
        purchasingAccountScope = nil
        interactiveOrderID = nil
        interactiveRevision = nil
        interactiveAttempt = nil
    }

    private func beginInteractionDeadline(attempt: UUID, orderID: UUID) {
        interactionDeadline?.cancel()
        interactionDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            guard let self, self.interactiveAttempt == attempt, self.interactiveOrderID == orderID else { return }
            self.purchaseLog.notice("Purchase interaction ended reason=awaitingAppleOrDelivery")
            let hasTransaction = self.purchaseLedger.orders[orderID]?.transactionID != nil
            self.releaseInteraction(orderID: orderID, pending: hasTransaction)
            if !hasTransaction {
                self.notice = AccountEntryNotice(title: "Waiting for Apple",
                    explanation: "Apple has not returned the purchase result yet. Please do not submit it again. Nana will continue when the result arrives.")
            }
        }
    }

    private func queuedTransactions(productID: String) -> [SKPaymentTransaction] {
        var unique: [ObjectIdentifier: SKPaymentTransaction] = [:]
        for transaction in SKPaymentQueue.default().transactions + Array(observedTransactions.values) + Array(bufferedTransactions.values)
            where transaction.payment.productIdentifier == productID {
            unique[ObjectIdentifier(transaction)] = transaction
        }
        return Array(unique.values)
    }

    private func unfinishedOrders(for binding: NanaPurchaseBinding) -> [NanaPurchaseOrder] {
        purchaseLedger.orders.values.filter {
            $0.binding.bundleID == binding.bundleID && $0.binding.productID == binding.productID &&
                $0.state != .finished && $0.state != .unpaid
        }
    }

    private func mayProceedPastReview(_ order: NanaPurchaseOrder, replacement: NanaPurchaseBinding) -> Bool {
        guard order.isIsolatedLegacyPreorder, replacement.source == .ablyServer,
              let original = order.binding.confirmation, let incoming = replacement.confirmation else { return false }
        return original.orderCode != incoming.orderCode && order.binding.sharesSettlementScope(with: replacement)
    }

    private func purchaseBlock(for binding: NanaPurchaseBinding) -> NanaPurchaseBlock? {
        let queued = queuedTransactions(productID: binding.productID)
        if !queued.isEmpty {
            purchaseLog.notice("Purchase queue pending count=\(queued.count)")
            if queued.contains(where: { $0.transactionState == .deferred }) { return .appleApprovalPending }
            if queued.contains(where: { $0.transactionState == .purchased || $0.transactionState == .restored }) { return .deliveryPending }
            return .appleQueuePending
        }
        let pending = unfinishedOrders(for: binding).filter { !mayProceedPastReview($0, replacement: binding) }
        guard !pending.isEmpty else { return nil }
        purchaseLog.notice("Purchase ledger pending count=\(pending.count)")
        if pending.contains(where: { $0.transactionID != nil }) { return .deliveryPending }
        if pending.contains(where: { $0.state == .needsReview || $0.binding.source == .legacyUnknown }) { return .reviewRequired }
        if pending.contains(where: { $0.observedAppleStates?.contains("deferred") == true }) { return .appleApprovalPending }
        return pending.allSatisfy(\.isUnobservedLegacyPreorder) ? .legacyPreorderUnresolved : .submissionUnresolved
    }

    private func isolateBlockingLegacyPreorder(for replacement: NanaPurchaseBinding) throws {
        guard replacement.source == .ablyServer, let incoming = replacement.confirmation,
              UIApplication.shared.applicationState == .active, accountScope == replacement.owner,
              interactiveOrderID == nil, interactionDeadline == nil,
              purchaseLedger.ready, purchaseLedger.unreadableAccounts.isEmpty, legacyMigrationComplete else { return }
        let candidates = unfinishedOrders(for: replacement).filter { !mayProceedPastReview($0, replacement: replacement) }
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.state == .awaitingApple, candidate.isUnobservedLegacyPreorder,
              candidate.legacyPreorderReview == nil,
              candidate.binding.sharesSettlementScope(with: replacement),
              let original = candidate.binding.confirmation, original.orderCode != incoming.orderCode,
              !original.orderCode.isEmpty, !original.messageID.isEmpty else {
            if !candidates.isEmpty { purchaseLog.notice("Legacy preorder kept reason=ineligibleOrAmbiguous count=\(candidates.count)") }
            return
        }
        guard queuedTransactions(productID: replacement.productID).isEmpty,
              !transactionOrders.values.contains(candidate.binding.id),
              processing.isEmpty, retryTasks.isEmpty, recoveryScan == nil else {
            purchaseLog.notice("Legacy preorder kept reason=queueOrRecoveryActive")
            return
        }
        let completed = purchaseLedger.orders.values.filter {
            $0.binding.id != candidate.binding.id && $0.binding.sharesSettlementScope(with: candidate.binding) &&
                $0.state == .finished && $0.delivered && $0.transactionID?.isEmpty == false &&
                ($0.environment == "sandbox" || $0.environment == "production") &&
                ($0.quantity == nil || $0.quantity == 1) &&
                $0.binding.confirmation?.orderCode != original.orderCode &&
                $0.binding.confirmation?.orderCode != incoming.orderCode
        }.sorted { $0.binding.id.uuidString < $1.binding.id.uuidString }
        guard let evidence = completed.first else {
            purchaseLog.notice("Legacy preorder kept reason=missingCompletedOrderEvidence")
            return
        }
        try purchaseLedger.isolateLegacyPreorder(candidate, completedOrder: evidence)
        purchaseLog.notice("Legacy preorder isolated reason=preservedForReviewWithCompletedOrderEvidence")
    }

    private func removeObservedTransactions(_ transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            let identity = ObjectIdentifier(transaction)
            observedTransactions[identity] = nil
            transactionOrders[identity] = nil
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

    private func transactionKey(_ transaction: SKPaymentTransaction) -> String? {
        guard let id = transaction.transactionIdentifier, !id.isEmpty,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return bundleID + ":" + id
    }

    private func associatedOrder(_ transaction: SKPaymentTransaction) -> NanaPurchaseOrder? {
        let transactionID = transaction.transactionIdentifier
        let username = transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:))
        let byID = purchaseLedger.orders.values.filter {
            transactionID != nil && $0.transactionID == transactionID
        }
        let byUsername = purchaseLedger.orders.values.filter {
            guard let saved = $0.binding.applicationUsername.flatMap(UUID.init(uuidString:)) else { return false }
            return username == saved
        }
        let identity = ObjectIdentifier(transaction)
        let cachedOrder = transactionOrders[identity].flatMap { purchaseLedger.orders[$0] }
        let candidates = byID.isEmpty ? (byUsername.isEmpty ? cachedOrder.map { [$0] } ?? [] : byUsername) : byID
        guard candidates.count == 1, let order = candidates.first,
              byUsername.isEmpty || (byUsername.count == 1 && byUsername.first?.binding.id == order.binding.id),
              cachedOrder == nil || cachedOrder?.binding.id == order.binding.id,
              order.binding.bundleID == Bundle.main.bundleIdentifier,
              order.binding.productID == transaction.payment.productIdentifier,
              order.binding.productType == "consumable", transaction.payment.quantity == 1,
              order.transactionID == nil || order.transactionID == transactionID else { return nil }
        if let rawUsername = transaction.payment.applicationUsername, !rawUsername.isEmpty {
            let expected = order.binding.applicationUsername.flatMap(UUID.init(uuidString:)) ?? order.binding.appAccountToken
            guard let username, username == expected else { return nil }
        }
        observedTransactions[identity] = transaction
        transactionOrders[identity] = order.binding.id
        return order
    }

    private func receive(_ transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            observedTransactions[ObjectIdentifier(transaction)] = transaction
            if let key = transactionKey(transaction) { bufferedTransactions[key] = transaction }
        }
        do { try prepareRecoveryLedger() } catch {
            for transaction in transactions where transaction.transactionState != .purchasing {
                releaseUnresolvedInteraction(transaction)
            }
            return
        }
        for transaction in transactions {
            var order = associatedOrder(transaction)
            if var observed = order {
                if observed.mayResumeIsolatedLegacyPreorder {
                    switch transaction.transactionState {
                    case .purchasing, .deferred:
                        observed.state = .awaitingApple
                        observed.lastFailure = "lateAppleTransactionObserved"
                    case .purchased:
                        if let transactionID = transaction.transactionIdentifier, !transactionID.isEmpty {
                            observed.transactionID = transactionID
                            observed.state = .paid
                            observed.lastFailure = "lateAppleTransactionObserved"
                        }
                    case .failed:
                        observed.state = .unpaid
                        observed.lastFailure = "lateAppleFailureObserved"
                    case .restored: break
                    @unknown default: break
                    }
                }
                let state: String
                switch transaction.transactionState {
                case .purchasing: state = "purchasing"
                case .deferred: state = "deferred"
                case .purchased: state = "purchased"
                case .failed: state = "failed"
                case .restored: state = "restored"
                @unknown default: state = "unknown"
                }
                observed.observedAppleStates = (observed.observedAppleStates ?? []).union([state])
                observed.submissionStage = "observedByApple"
                do { order = try purchaseLedger.save(observed) }
                catch { releaseUnresolvedInteraction(transaction); continue }
            }
            switch transaction.transactionState {
            case .purchasing:
                break
            case .deferred:
                if let order { releaseInteraction(orderID: order.binding.id, pending: true) }
            case .failed:
                if let order {
                    do { try markUnpaid(order.binding.id) }
                    catch { releaseInteraction(orderID: order.binding.id, pending: true); continue }
                    if interactiveOrderID == order.binding.id {
                        let cancelled = (transaction.error as? SKError)?.code == .paymentCancelled
                        if !cancelled {
                            notice = AccountEntryNotice(title: "Purchase unavailable", explanation: "Apple couldn't complete this purchase. Please try again.")
                        }
                        releaseInteraction(orderID: order.binding.id)
                    }
                }
                SKPaymentQueue.default().finishTransaction(transaction)
                if let key = transactionKey(transaction) { bufferedTransactions[key] = nil }
            case .purchased:
                guard let key = transactionKey(transaction) else {
                    if let order { releaseInteraction(orderID: order.binding.id, pending: true) }
                    continue
                }
                if schedule(transaction, key: key) == nil { releaseUnresolvedInteraction(transaction) }
            case .restored:
                if let order { releaseInteraction(orderID: order.binding.id, pending: true) }
            @unknown default:
                if let order { releaseInteraction(orderID: order.binding.id, pending: true) }
            }
        }
    }

    private func releaseUnresolvedInteraction(_ transaction: SKPaymentTransaction) {
        guard let id = interactiveOrderID,
              transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)) == id else { return }
        releaseInteraction(orderID: id, pending: true)
    }

    @discardableResult
    private func schedule(_ transaction: SKPaymentTransaction, key: String) -> Task<Bool, Never>? {
        if let task = processing[key] { return task }
        guard purchaseLedger.ready, let order = associatedOrder(transaction) else { return nil }
        retryTasks.removeValue(forKey: key)?.cancel()
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let completed = await self.process(transaction)
            self.processing[key] = nil
            self.releaseInteraction(orderID: order.binding.id, pending: !completed)
            if completed {
                self.bufferedTransactions[key] = nil
                self.retryAttempts[key] = nil
            } else {
                self.scheduleRetry(transaction, key: key)
            }
            return completed
        }
        processing[key] = task
        return task
    }

    private func verifiedReceipt(for order: NanaPurchaseOrder, transactionID: String) async throws -> NanaVerifiedAppReceipt {
        func read() async throws -> NanaVerifiedAppReceipt {
            let receipt = try await NanaAppReceiptVerifier.readAndValidate()
            try receipt.validatePurchase(transactionID: transactionID, productID: order.binding.productID, quantity: 1)
            return receipt
        }
        do { return try await read() } catch {
            guard interactiveOrderID == order.binding.id, interactiveRevision == purchaseSessionRevision,
                  UIApplication.shared.applicationState == .active,
                  receiptRefreshAttempts.insert(order.binding.id).inserted else { throw error }
            try await receiptRequests.refreshReceipt()
            return try await read()
        }
    }

    private func process(_ transaction: SKPaymentTransaction) async -> Bool {
        guard transaction.transactionState == .purchased, let transactionID = transaction.transactionIdentifier else { return false }
        do {
            guard var order = associatedOrder(transaction), order.binding.source != .legacyUnknown,
                  order.state != .needsReview else { return false }
            if order.delivered {
                guard order.transactionID == transactionID,
                      order.environment == "production" || order.environment == "sandbox" else { return false }
                return try finish(transaction, order: order)
            }
            if order.transactionID == nil {
                order.transactionID = transactionID
                order.state = .paid
                order = try purchaseLedger.save(order)
            }
            let receipt = try await verifiedReceipt(for: order, transactionID: transactionID)
            guard let current = purchaseLedger.orders[order.binding.id], current.binding == order.binding,
                  current.transactionID == transactionID, current.state != .needsReview,
                  current.environment == nil || current.environment == receipt.environment else { return false }
            order = current
            order.environment = receipt.environment
            if order.state == .awaitingApple || order.state == .unpaid { order.state = .paid }
            order = try purchaseLedger.save(order)
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
                    let deliveryKey = order.binding.bundleID + ":" + receipt.environment + ":" + transactionID
                    let oldID = UInt64(transactionID).flatMap { String($0) == transactionID ? $0 : nil }
                    let wasDelivered = (record.processedStoreTransactionIDs ?? []).contains(deliveryKey) ||
                        oldID.map { record.processedTransactionIDs.contains($0) } == true
                    guard !(ledger.removedStoreTransactionIDs ?? []).contains(deliveryKey),
                          !(oldID.map { (ledger.removedAccountTransactionIDs ?? []).contains($0) } ?? false),
                          !ledger.accounts.contains(where: { owner, other in
                              owner != order.binding.owner && ((other.processedStoreTransactionIDs ?? []).contains(deliveryKey) ||
                                  oldID.map { other.processedTransactionIDs.contains($0) } == true)
                          }) else { return false }
                    if !wasDelivered {
                        order.state = .deliveringLocal
                        try purchaseLedger.save(order)
                        let (newBalance, overflow) = record.balance.addingReportingOverflow(coins)
                        guard !overflow else { return false }
                        record.balance = newBalance
                        record.processedStoreTransactionIDs = (record.processedStoreTransactionIDs ?? []).union([deliveryKey])
                        if let oldID { record.processedTransactionIDs.insert(oldID) }
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
                          let deviceID = order.binding.deviceID else { return false }
                    try await authentication.confirmPurchase(transactionID: transactionID, receipt: receipt.data.base64EncodedString(),
                        confirmation: confirmation, version: version, deviceID: deviceID)
                    guard let current = purchaseLedger.orders[order.binding.id], current.binding == order.binding,
                          current.transactionID == transactionID, current.environment == receipt.environment,
                          current.state != .needsReview else { return false }
                    order = current
                    order.state = .serverConfirmed
                    order = try purchaseLedger.save(order)
                case .legacyUnknown:
                    return false
                }
            }
            return try finish(transaction, order: order)
        } catch { return false }
    }

    private func finish(_ transaction: SKPaymentTransaction, order: NanaPurchaseOrder) throws -> Bool {
        guard order.delivered else { return false }
        var persisted = try purchaseLedger.save(order)
        guard persisted.delivered else { return false }
        SKPaymentQueue.default().finishTransaction(transaction)
        persisted.state = .finished
        try purchaseLedger.save(persisted)
        return true
    }

    private func scheduleRetry(_ transaction: SKPaymentTransaction, key: String) {
        let attempts = retryAttempts[key, default: 0]
        guard attempts < 3, let order = associatedOrder(transaction),
              order.binding.source != .legacyUnknown, order.state != .needsReview else { return }
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
    case invalidProductIdentifier
    case paymentsRestricted
    case unsupportedProduct
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
        }
        .allowsHitTesting(true)
    }
}
