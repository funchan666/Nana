import Foundation
import TPInAppReceipt

struct NanaVerifiedAppReceipt: Sendable {
    let data: Data
    let environment: String
    let purchases: [InAppPurchase]

    func validatePurchase(transactionID: String, productID: String, quantity: Int) throws {
        let matches = purchases.filter { $0.transactionIdentifier == transactionID }
        guard matches.count == 1, let purchase = matches.first,
              purchase.productIdentifier == productID, purchase.quantity == quantity, quantity == 1,
              purchase.cancellationDate == nil, purchase.subscriptionExpirationDate == nil,
              purchase.productType == .consumable || purchase.productType == .unknown else {
            throw NanaReceiptError.purchaseMismatch
        }
    }
}

enum NanaAppReceiptVerifier {
    static func readAndValidate() async throws -> NanaVerifiedAppReceipt {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let data = try? Data(contentsOf: receiptURL), !data.isEmpty, data.count <= 8 * 1_024 * 1_024,
              let rootURL = Bundle.main.url(forResource: "NanaAppleRoot", withExtension: "cer"),
              let root = try? Data(contentsOf: rootURL),
              let bundleID = Bundle.main.bundleIdentifier,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            throw NanaReceiptError.unavailable
        }
        let receipt = try AppReceipt.receipt(from: data)
        guard receipt.hasValidStructure, let leaf = receipt.certificates.first else {
            throw NanaReceiptError.invalid
        }
        let environment: String
        switch receipt.environment {
        case .production: environment = "production"
        case .sandbox, .productionSandbox: environment = "sandbox"
        default: throw NanaReceiptError.invalid
        }
        guard let deviceID = await DeviceIdentifier.data else { throw NanaReceiptError.unavailable }
        let validation = await receipt.validate(rootCertificate: root, deviceIdentifier: deviceID)
        let chain = try X509ChainVerifier(rootCertificates: [root])
        let chainResult = await chain.verify(leaf: leaf, intermediate: Array(receipt.certificates.dropFirst()),
            policy: [.appleX509Basic, .appStoreReceipt, .validationTime(receipt.creationDate)])
        guard validation.isValid, chainResult.isValid,
              await HashVerifier(deviceIdentifier: deviceID).verify(receipt).isValid,
              receipt.bundleIdentifier == bundleID, receipt.appVersion == build else {
            throw NanaReceiptError.invalid
        }
        return NanaVerifiedAppReceipt(data: data, environment: environment, purchases: receipt.purchases)
    }
}

enum NanaReceiptError: Error { case unavailable, invalid, purchaseMismatch }
