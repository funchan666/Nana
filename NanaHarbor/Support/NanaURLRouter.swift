import Foundation
import UIKit

final class NanaURLRouter {
    static let shared = NanaURLRouter()
    private init() { }

    func receive(_ url: URL) {
        guard let scheme = url.scheme,
              scheme.caseInsensitiveCompare(Bundle.main.bundleIdentifier ?? "") == .orderedSame else { return }
    }
}
