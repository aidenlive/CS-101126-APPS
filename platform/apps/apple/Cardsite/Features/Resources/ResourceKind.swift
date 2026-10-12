import Foundation
import CardsiteKit

/// The six resource types this folder manages, with the names, glyphs and
/// copy every surface (list, editors, More, the New menu) shows for them.
///
/// Titles and glyphs match `ResourceKindInfo` (the `@csxbase/link-model`
/// registry's wording); list and empty-state copy is the web's (en.json).
enum ResourceKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case vcard
    case event
    case paymentLink
    case file
    case staticPage
    case splash

    var id: String { rawValue }

    /// The link-backed endpoint, or nil for splash pages (their own table).
    var linkType: ManagedResourceType? {
        switch self {
        case .vcard: return .vcard
        case .event: return .event
        case .paymentLink: return .paymentLink
        case .file: return .file
        case .staticPage: return .staticPage
        case .splash: return nil
        }
    }

    /// Splash pages have no address and no switch.
    var hasAddress: Bool { self != .splash }

    var supportsDuplicate: Bool { linkType?.supportsDuplicate ?? false }

    /// Singular, as the registry spells it: "vCard", "File link".
    var title: String {
        ResourceKindInfo(type: wireType).title
    }

    /// The list screen's title and the sidebar name.
    var pluralTitle: String {
        switch self {
        case .vcard: return String(localized: "vCards")
        case .event: return String(localized: "Events")
        case .paymentLink: return String(localized: "Payment links")
        case .file: return String(localized: "File links")
        case .staticPage: return String(localized: "Static pages")
        case .splash: return String(localized: "Splash pages")
        }
    }

    var systemImage: String {
        ResourceKindInfo(type: wireType).systemImage
    }

    /// `type` on the wire; `splash_page` for splash pages, as the registry names it.
    var wireType: String {
        linkType?.wireType ?? "splash_page"
    }

    /// The web's page description.
    var blurb: String {
        switch self {
        case .vcard: return String(localized: "Digital contact cards, one tap to save.")
        case .event: return String(localized: "A dated event page that exports to a calendar.")
        case .paymentLink: return String(localized: "Short URLs that send buyers straight to your checkout.")
        case .file: return String(localized: "A hosted file served from a URL you choose.")
        case .staticPage: return String(localized: "An uploaded HTML page served from your domain.")
        case .splash: return String(localized: "An interstitial shown before a link resolves.")
        }
    }

    var createTitle: String {
        switch self {
        case .vcard: return String(localized: "Create vCard")
        case .event: return String(localized: "Create event")
        case .paymentLink: return String(localized: "Create payment link")
        case .file: return String(localized: "Create file link")
        case .staticPage: return String(localized: "Create static page")
        case .splash: return String(localized: "Create splash page")
        }
    }

    var editTitle: String {
        switch self {
        case .vcard: return String(localized: "Edit vCard")
        case .event: return String(localized: "Edit event")
        case .paymentLink: return String(localized: "Edit payment link")
        case .file: return String(localized: "Edit file link")
        case .staticPage: return String(localized: "Edit static page")
        case .splash: return String(localized: "Edit splash page")
        }
    }

    var emptyTitle: String {
        switch self {
        case .vcard: return String(localized: "No vCards yet")
        case .event: return String(localized: "No events yet")
        case .paymentLink: return String(localized: "No payment links yet")
        case .file: return String(localized: "No file links yet")
        case .staticPage: return String(localized: "No static pages yet")
        case .splash: return String(localized: "No splash pages yet")
        }
    }

    var emptyMessage: String {
        switch self {
        case .vcard: return String(localized: "Create your first vCard to share your contact information.")
        case .event: return String(localized: "Create one to share event details via a short link.")
        case .paymentLink: return String(localized: "Create one to give a checkout page a short, branded URL.")
        case .file: return String(localized: "Upload a file to share via a short link.")
        case .staticPage: return String(localized: "Upload an HTML or ZIP file to create one.")
        case .splash: return String(localized: "Create one to add an interstitial page before your links.")
        }
    }

    var searchPrompt: String {
        switch self {
        case .vcard: return String(localized: "Search names, companies and addresses")
        case .event: return String(localized: "Search events, places and addresses")
        case .paymentLink: return String(localized: "Search addresses and checkouts")
        case .file: return String(localized: "Search files and addresses")
        case .staticPage: return String(localized: "Search addresses")
        case .splash: return String(localized: "Search splash pages")
        }
    }

    /// The address field's label and help, from the web's forms.
    var addressLabel: String {
        switch self {
        case .vcard: return String(localized: "Card address")
        case .event: return String(localized: "Event address")
        case .paymentLink: return String(localized: "Payment link address")
        case .file: return String(localized: "File address")
        case .staticPage: return String(localized: "Page address")
        case .splash: return ""
        }
    }

    var addressHelp: String {
        switch self {
        case .vcard: return String(localized: "Where this contact card lives.")
        case .event: return String(localized: "Where this event page lives.")
        case .paymentLink: return String(localized: "The short URL you share with buyers.")
        case .file: return String(localized: "Where this file is served from.")
        case .staticPage: return String(localized: "Where this page lives.")
        case .splash: return ""
        }
    }

    var deleteConfirmation: String {
        switch self {
        case .vcard: return String(localized: "Delete this vCard?")
        case .event: return String(localized: "Delete this event?")
        case .paymentLink: return String(localized: "Delete this payment link?")
        case .file: return String(localized: "Delete this file link?")
        case .staticPage: return String(localized: "Delete this static page?")
        case .splash: return String(localized: "Delete this splash page?")
        }
    }

    var deleteConsequence: String {
        switch self {
        case .file, .staticPage:
            return String(localized: "Its address stops resolving immediately and the uploaded file is removed. This can't be undone.")
        case .splash:
            return String(localized: "Links that show it go straight to their destination. This can't be undone.")
        default:
            return String(localized: "Its address stops resolving immediately. This can't be undone.")
        }
    }

    /// The `res.<kind>.*` accessibility identifier stem.
    var identifier: String {
        switch self {
        case .vcard: return "vcard"
        case .event: return "event"
        case .paymentLink: return "payment"
        case .file: return "file"
        case .staticPage: return "static"
        case .splash: return "splash"
        }
    }

    init(linkType: ManagedResourceType) {
        switch linkType {
        case .vcard: self = .vcard
        case .event: self = .event
        case .paymentLink: self = .paymentLink
        case .file: self = .file
        case .staticPage: self = .staticPage
        }
    }
}

extension Notification.Name {
    /// Posted (object: the kind's raw value) when an editor opened outside a
    /// list, such as from the New menu, creates something, so the list on
    /// screen shows it.
    static let resourceCreated = Notification.Name("cardsite.resourceCreated")
}
