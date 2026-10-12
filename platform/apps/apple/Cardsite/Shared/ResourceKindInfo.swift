import Foundation
import CardsiteKit

/// The name and glyph of each resource type the API registers
/// (models.LinkTypes on the server), worded as the web's
/// `@csxbase/link-model` registry spells them.
struct ResourceKindInfo: Equatable, Sendable {
    let title: String
    let systemImage: String
    /// Pages built in an editor rather than pointing elsewhere. The web
    /// tints their thumbnails; Home does the same.
    let isComposed: Bool

    init(type: String) {
        switch type {
        case LinkKind.shortLink:
            self.init(String(localized: "Short link"), "link", composed: false)
        case LinkKind.bioPage:
            self.init(String(localized: "Bio page"), "person.crop.square", composed: true)
        case "vcard":
            self.init(String(localized: "vCard"), "person.text.rectangle", composed: true)
        case "event":
            self.init(String(localized: "Event"), "calendar", composed: true)
        case "file":
            self.init(String(localized: "File link"), "doc", composed: false)
        case "static":
            self.init(String(localized: "Static page"), "chevron.left.forwardslash.chevron.right", composed: true)
        case "splash_page":
            self.init(String(localized: "Splash page"), "hourglass", composed: false)
        case "payment_link":
            self.init(String(localized: "Payment link"), "creditcard", composed: true)
        default:
            self.init(String(localized: "Resource"), "square.dashed", composed: false)
        }
    }

    private init(_ title: String, _ systemImage: String, composed: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.isComposed = composed
    }
}

extension Resource {
    var kindInfo: ResourceKindInfo { ResourceKindInfo(type: type) }
}
