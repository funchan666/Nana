import Foundation
import Security

struct NanaPurchaseConfirmation: Codable, Equatable {
    let origin: String
    let path: String
    let versionField: String
    let deviceField: String
    let transactionField: String
    let receiptField: String
    let orderField: String
    let successField: String
    let orderCode: String
    let messageID: String
    let requestID: UUID
    var explicitMessageID: String? = nil

    static func current(orderCode: String, messageID: String, requestID: UUID, explicitMessageID: String? = nil) -> Self {
        Self(origin: NanaAServiceConfiguration.interfaceBaseURL.absoluteString,
             path: IntegrationContract.settlementPath,
             versionField: ConfiguredWireFields.release_tag,
             deviceField: ConfiguredWireFields.device_fingerprint,
             transactionField: ConfiguredWireFields.store_receipt_id,
             receiptField: ConfiguredWireFields.receipt_blob,
             orderField: ConfiguredWireFields.order_reference,
             successField: ConfiguredWireFields.code,
             orderCode: orderCode, messageID: messageID, requestID: requestID,
             explicitMessageID: explicitMessageID)
    }
}

enum NanaPurchaseSource: String, Codable { case hostLocal, ablyServer, legacyUnknown }
enum NanaPurchaseState: String, Codable {
    case awaitingApple, unpaid, paid, deliveringLocal, localDelivered, serverConfirmed, finished, needsReview
}

struct NanaPurchaseBinding: Codable, Equatable {
    let id: UUID
    let source: NanaPurchaseSource
    let productID: String
    let productType: String
    let owner: String
    let appAccountToken: UUID?
    let bundleID: String
    let version: String?
    let deviceID: String?
    let walletID: UUID?
    let localCoins: Int?
    let confirmation: NanaPurchaseConfirmation?
    let legacyKey: String?
    let legacyOrderCode: String?
    var applicationUsername: String? = nil
}

struct NanaPurchaseOrder: Codable, Equatable {
    let schemaVersion: Int
    let binding: NanaPurchaseBinding
    var transactionID: String?
    var environment: String?
    var state: NanaPurchaseState
    var retryCount: Int
    var lastFailure: String?
    var submissionVersion: Int? = nil
    var submissionStage: String? = nil
    var observedAppleStates: Set<String>? = nil
    var quantity: Int? = nil

    var delivered: Bool {
        (binding.source == .hostLocal && state == .localDelivered) ||
        (binding.source == .ablyServer && state == .serverConfirmed) || state == .finished
    }
}

@MainActor
final class NanaPurchaseLedger {
    private let service = "com.nanalantern.harbortide.purchase-orders.v1"
    private(set) var orders: [UUID: NanaPurchaseOrder] = [:]
    private(set) var unreadableAccounts = Set<String>()
    private(set) var ready = false

    private func query(_ account: String? = nil) -> [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrSynchronizable as String: false]
        if let account { value[kSecAttrAccount as String] = account }
        return value
    }

    func reload() throws {
        ready = false
        var request = query()
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound {
            orders = [:]
            unreadableAccounts = []
            ready = true
            return
        }
        guard status == errSecSuccess, let attributes = result as? [[String: Any]] else {
            throw NanaCoinPurchaseError.storageUnavailable
        }
        var loaded: [UUID: NanaPurchaseOrder] = [:]
        var unreadable = Set<String>()
        for item in attributes {
            guard let account = item[kSecAttrAccount as String] as? String else {
                throw NanaCoinPurchaseError.storageUnavailable
            }
            let data = try readData(account)
            guard let data, let order = try? JSONDecoder().decode(NanaPurchaseOrder.self, from: data),
                  order.schemaVersion == 1, order.binding.id.uuidString == account else {
                unreadable.insert(account)
                continue
            }
            loaded[order.binding.id] = order
        }
        orders = loaded
        unreadableAccounts = unreadable
        ready = true
    }

    private func readData(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NanaCoinPurchaseError.storageUnavailable
        }
        return data
    }

    @discardableResult
    func save(_ proposed: NanaPurchaseOrder) throws -> NanaPurchaseOrder {
        try save(proposed, mayMergeDuplicate: true)
    }

    private func save(_ proposed: NanaPurchaseOrder, mayMergeDuplicate: Bool) throws -> NanaPurchaseOrder {
        guard ready else { throw NanaCoinPurchaseError.storageUnavailable }
        let account = proposed.binding.id.uuidString
        let existingData = try readData(account)
        if let existingData {
            let existing = try JSONDecoder().decode(NanaPurchaseOrder.self, from: existingData)
            guard existing.binding == proposed.binding,
                  existing.submissionVersion == nil || existing.submissionVersion == proposed.submissionVersion,
                  existing.quantity == nil || existing.quantity == proposed.quantity,
                  (existing.observedAppleStates ?? []).isSubset(of: proposed.observedAppleStates ?? []),
                  existing.transactionID == nil || existing.transactionID == proposed.transactionID,
                  existing.environment == nil || existing.environment == proposed.environment else {
                throw NanaCoinPurchaseError.storageUnavailable
            }
            if existing.delivered {
                guard proposed.state == existing.state || proposed.state == .finished else {
                    orders[existing.binding.id] = existing
                    return existing
                }
            }
            if (existing.state == .paid || existing.state == .deliveringLocal || existing.state == .needsReview),
               proposed.state == .awaitingApple || proposed.state == .unpaid {
                throw NanaCoinPurchaseError.storageUnavailable
            }
        }
        if let transactionID = proposed.transactionID {
            guard !orders.values.contains(where: {
                $0.binding.id != proposed.binding.id && $0.transactionID == transactionID &&
                ($0.environment == nil || proposed.environment == nil || $0.environment == proposed.environment)
            }) else { throw NanaCoinPurchaseError.storageUnavailable }
        }
        let data = try JSONEncoder().encode(proposed)
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status: OSStatus
        if existingData != nil {
            status = SecItemUpdate(query(account) as CFDictionary, values as CFDictionary)
        } else {
            var insertion = query(account)
            values.forEach { insertion[$0.key] = $0.value }
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        if status == errSecDuplicateItem, mayMergeDuplicate {
            return try save(proposed, mayMergeDuplicate: false)
        }
        guard status == errSecSuccess,
              let storedData = try readData(account),
              let stored = try? JSONDecoder().decode(NanaPurchaseOrder.self, from: storedData), stored == proposed else {
            ready = false
            throw NanaCoinPurchaseError.storageUnavailable
        }
        orders[stored.binding.id] = stored
        return stored
    }
}
