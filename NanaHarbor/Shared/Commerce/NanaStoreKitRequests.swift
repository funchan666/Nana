import Foundation
import StoreKit
import OSLog

struct NanaStoreProductResult {
    let products: [SKProduct]
    let invalidProductIdentifiers: Set<String>
}

@MainActor
final class NanaStoreKitRequests: NSObject, SKProductsRequestDelegate {
    private enum Completion {
        case products(CheckedContinuation<NanaStoreProductResult, Error>)
        case receipt(CheckedContinuation<Void, Error>)
    }

    private struct Pending {
        let request: SKRequest
        let completion: Completion
        let deadline: Task<Void, Never>
        var products: NanaStoreProductResult?
        var finished = false
    }

    private var pending: [ObjectIdentifier: Pending] = [:]
    private let log = Logger(subsystem: "com.nanalantern.harbortide", category: "StoreProducts")

    func products(identifiers: Set<String>) async throws -> NanaStoreProductResult {
        let request = SKProductsRequest(productIdentifiers: identifiers)
        let key = ObjectIdentifier(request)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                begin(request, completion: .products(continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(key, error: CancellationError()) }
        }
    }

    func refreshReceipt() async throws {
        let request = SKReceiptRefreshRequest(receiptProperties: nil)
        let key = ObjectIdentifier(request)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                begin(request, completion: .receipt(continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(key, error: CancellationError()) }
        }
    }

    func cancelAll() {
        for key in Array(pending.keys) { fail(key, error: CancellationError()) }
    }

    private func begin(_ request: SKRequest, completion: Completion) {
        let key = ObjectIdentifier(request)
        let deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.fail(key, error: NanaStoreRequestError.timedOut)
        }
        pending[key] = Pending(request: request, completion: completion, deadline: deadline)
        request.delegate = self
        request.start()
    }

    private func take(_ key: ObjectIdentifier) -> Pending? {
        guard let value = pending.removeValue(forKey: key) else { return nil }
        value.deadline.cancel()
        value.request.delegate = nil
        return value
    }

    private func fail(_ key: ObjectIdentifier, error: Error) {
        guard let value = take(key) else { return }
        value.request.cancel()
        switch value.completion {
        case .products(let continuation): continuation.resume(throwing: error)
        case .receipt(let continuation): continuation.resume(throwing: error)
        }
    }

    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(request)
            guard self.pending[key] != nil else { return }
            self.pending[key]?.products = NanaStoreProductResult(products: response.products,
                invalidProductIdentifiers: Set(response.invalidProductIdentifiers))
            for identifier in response.invalidProductIdentifiers {
                self.log.error("Product rejected by App Store id=\(identifier, privacy: .public)")
            }
            self.log.notice("Product response valid=\(response.products.count) invalid=\(response.invalidProductIdentifiers.count)")
            self.completeProductsIfReady(key)
        }
    }

    private func completeProductsIfReady(_ key: ObjectIdentifier) {
        guard let value = pending[key], value.finished, let products = value.products,
              case .products(let continuation) = value.completion else { return }
        _ = take(key)
        continuation.resume(returning: products)
    }

    nonisolated func requestDidFinish(_ request: SKRequest) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let key = ObjectIdentifier(request)
            if request is SKProductsRequest {
                self.pending[key]?.finished = true
                self.completeProductsIfReady(key)
            } else if let value = self.take(key), case .receipt(let continuation) = value.completion {
                continuation.resume()
            }
        }
    }

    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.fail(ObjectIdentifier(request), error: error) }
    }
}

enum NanaStoreRequestError: Error { case timedOut }

final class NanaPaymentQueueObserver: NSObject, SKPaymentTransactionObserver {
    private let receive: @MainActor ([SKPaymentTransaction]) -> Void
    private let removed: @MainActor ([SKPaymentTransaction]) -> Void

    init(receive: @escaping @MainActor ([SKPaymentTransaction]) -> Void,
         removed: @escaping @MainActor ([SKPaymentTransaction]) -> Void) {
        self.receive = receive
        self.removed = removed
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor [receive] in receive(transactions) }
    }

    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor [removed] in removed(transactions) }
    }

    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        false
    }
}
