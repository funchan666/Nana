// Generated runtime v2; use the paired ConfiguredEventDecoder template.
// Deployment mappings belong in Docs, never in App resources.
import Foundation

enum IntegrationContract {
    static let namespace: String = "nana"
    static let baseURLString: String? = "https://lantern.nanacc.top"
    static let ablyClientID: String = "app"
    static let serverClientIDs: [String] = ["serve"]
    static let allowsMissingSender: Bool = true
    static let acceptsSerializedExpiry: Bool = true
    static let continuationMode: Int = 2
    static let optionsPath: String = "/nana/harbor/doorway"
    static let entryPath: String = "/nana/harbor/tidepass"
    static let settlementPath: String = "/nana/harbor/coin-confirm"
    static let pageSignal: String = "HarborPageReady"
    static let pageDiscriminator: [String] = ["signal"]
    static let purchaseSignal: String = "LanternCheckout"
    static let purchaseDiscriminator: [String] = ["signal"]
    static let expirySignal: String = "HarborSessionEnded"
    static let expiryDiscriminator: [String] = ["signal"]
    static let externalSignal: String = "LanternExternalLink"
    static let externalDiscriminator: [String] = ["signal"]
    static let pageAddressPath: [String] = ["harbor", "destination"]
    static let purchaseItemPath: [String] = ["order", "product"]
    static let purchaseReferencePath: [String] = ["order", "reference"]
    static let externalAddressPath: [String] = ["navigation", "href"]
}

enum ConfiguredContentPaths {
    static let `bootstrap`: String = "/nana/harbor/bootstrap"
    static let `homeFeed`: String = "/nana/harbor/home-feed"
    static let `rooms`: String = "/nana/harbor/rooms"
    static let `auroraRoom`: String = "/nana/harbor/rooms/aurora"
    static let `avaProfile`: String = "/nana/harbor/profiles/ava"
    static let `echoesPost`: String = "/nana/harbor/posts/echoes"
    static let `search`: String = "/nana/harbor/search"
    static let `conversations`: String = "/nana/harbor/conversations"
    static let `avaMessages`: String = "/nana/harbor/conversations/ava/messages"
    static let `wallet`: String = "/nana/harbor/wallet"
    static let `gifts`: String = "/nana/harbor/gifts"
    static let `assetManifest`: String = "/nana/harbor/assets"
}

enum ConfiguredWireFields {
    static let `apple_assertion`: String = "apple_assertion"
    static let `apple_code`: String = "apple_code"
    static let `apple_lantern`: String = "apple_lantern"
    static let `apple_subject`: String = "apple_subject"
    static let `code`: String = "code"
    static let `data`: String = "data"
    static let `device_fingerprint`: String = "device_fingerprint"
    static let `email_tide`: String = "email_tide"
    static let `entry_context`: String = "entry_context"
    static let `entry_mode`: String = "entry_mode"
    static let `mailbox`: String = "mailbox"
    static let `message`: String = "message"
    static let `order_reference`: String = "order_reference"
    static let `pulse_token`: String = "pulse_token"
    static let `receipt_blob`: String = "receipt_blob"
    static let `register_current`: String = "register_current"
    static let `release_tag`: String = "release_tag"
    static let `room_delivery_kind`: String = "room_delivery_kind"
    static let `secret_phrase`: String = "secret_phrase"
    static let `store_receipt_id`: String = "store_receipt_id"
    static let `token`: String = "token"
    static let `visitor_harbor`: String = "visitor_harbor"
}
