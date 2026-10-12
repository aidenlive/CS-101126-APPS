import Foundation

// The five link-backed resource types besides short links and bio pages
// (vCards, events, payment links, file links, static pages), and splash
// pages. From fixtures 25a–25q and 21i/21j (ContractTests/fixtures) and the
// Go handlers in apps/api/internal/handlers (vcards.go, events.go,
// payment_links.go, file_links.go, static_pages.go, splash_pages.go).
//
// Server rules these types encode:
// - Each type is a row in `links`, so every row is link-shaped: `url` is
//   the slug, `settings` holds the type's fields.
// - Create takes the type's fields FLAT (`vcard_first_name`, `event_name`);
//   update takes them inside `settings`, and `settings` REPLACES what was
//   stored. Every typed settings value keeps the keys it does not edit in
//   `other` and writes them back, so a save from the app never drops a key
//   the web or a later server version set.
// - The gate (password, click limit, expiration URL, sensitive content)
//   lives in `settings` for every type and is enforced by the redirect for
//   every type. The stored password is a bcrypt digest under
//   `password_hash`: it is never decoded into a value or sent back. Saying
//   nothing about `password` keeps it, `password: ""` removes it.
// - Update handlers ignore `display_rules` and the schedule for these
//   types, and the vCard, file and static update handlers ignore
//   `domain_id`: the domain is chosen at creation.
// - File links and static pages are multipart on create AND update. On
//   update every field is optional; `clicks_limit` and `expiration_url`
//   are written only when non-empty, so they can be replaced but an
//   expiration URL cannot be cleared (a limit of "0" means no limit).
// - Splash pages are their own table: no slug, no enabled switch.
//   `settings` (secondary button, ads, custom code) is replaced on PUT.

// MARK: - Resource types

/// A link-backed resource type with its own endpoint.
public enum ManagedResourceType: String, Sendable, Hashable, CaseIterable, Codable {
    case vcard
    case event
    case paymentLink = "payment_link"
    case file
    case staticPage = "static"

    /// `type` on the wire (`models.LinkType*`).
    public var wireType: String { rawValue }

    /// The collection path under `/api/v1`.
    public var path: String {
        switch self {
        case .vcard: return "api/v1/vcards"
        case .event: return "api/v1/events"
        case .paymentLink: return "api/v1/payment-links"
        case .file: return "api/v1/files"
        case .staticPage: return "api/v1/static"
        }
    }

    /// `POST /links/{id}/duplicate` refuses types that own stored bytes
    /// (`duplicableLinkTypes`, ADR-0131).
    public var supportsDuplicate: Bool {
        switch self {
        case .vcard, .event, .paymentLink: return true
        case .file, .staticPage: return false
        }
    }

    /// Create and update are `multipart/form-data`.
    public var usesMultipart: Bool {
        self == .file || self == .staticPage
    }
}

// MARK: - Row

/// A vCard, event, payment link, file link or static page, as every
/// endpoint of these types returns it.
public struct ManagedResource: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    /// `vcard`, `event`, `payment_link`, `file` or `static`.
    public let type: String
    /// The address (`url` on the wire).
    public let slug: String
    /// A payment link's checkout URL (`location_url`); empty for the others.
    public let destination: String?
    public let domainID: Int?
    public let projectID: Int?
    /// The stored settings object, as sent. Read it through the typed views
    /// (``vcard``, ``event``…); `password_hash` is in here when set.
    public let settings: [String: JSONValue]
    public let clicks: Int
    public let isEnabled: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    public let lifecycleState: String?

    enum CodingKeys: String, CodingKey {
        case id, type, settings, clicks
        case workspaceID = "workspace_id"
        case slug = "url"
        case destination = "location_url"
        case domainID = "domain_id"
        case projectID = "project_id"
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lifecycleState = "lifecycle_state"
    }

    public init(id: Int, workspaceID: Int? = nil, type: ManagedResourceType, slug: String, destination: String? = nil,
                domainID: Int? = nil, projectID: Int? = nil, settings: [String: JSONValue] = [:], clicks: Int = 0,
                isEnabled: Bool = true, createdAt: Date? = nil, updatedAt: Date? = nil,
                lifecycleState: String? = "active") {
        self.id = id
        self.workspaceID = workspaceID
        self.type = type.wireType
        self.slug = slug
        self.destination = destination
        self.domainID = domainID
        self.projectID = projectID
        self.settings = settings
        self.clicks = clicks
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lifecycleState = lifecycleState
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        domainID = try c.decodeIfPresent(Int.self, forKey: .domainID)
        projectID = try c.decodeIfPresent(Int.self, forKey: .projectID)
        settings = try c.decodeIfPresent(JSONValue.self, forKey: .settings)?.objectValue ?? [:]
        clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        lifecycleState = try c.decodeIfPresent(String.self, forKey: .lifecycleState)
    }

    public var resourceType: ManagedResourceType? { ManagedResourceType(rawValue: type) }

    /// Anything other than "active" means the address is in its release window.
    public var isLapsing: Bool {
        guard let lifecycleState, !lifecycleState.isEmpty else { return false }
        return lifecycleState != "active"
    }

    /// The generic row shape (Home, search, statistics).
    public var resource: Resource {
        Resource(id: id, workspaceID: workspaceID, type: type, slug: slug, destination: destination,
                 clicks: clicks, isEnabled: isEnabled, createdAt: createdAt, updatedAt: updatedAt,
                 lifecycleState: lifecycleState)
    }

    // Typed views of `settings`.
    public var gate: ResourceGate { ResourceGate(json: settings) }
    public var vcard: VCardSettings { VCardSettings(json: settings) }
    public var event: EventSettings { EventSettings(json: settings) }
    public var paymentLink: PaymentLinkSettings { PaymentLinkSettings(json: settings) }
    public var file: FileLinkSettings { FileLinkSettings(json: settings) }
    public var staticPage: StaticPageSettings { StaticPageSettings(json: settings) }
}

// MARK: - Gate

/// Password, click limit, expiration URL and the sensitive-content warning:
/// the keys the redirect enforces for every type (handlers/redirect.go).
public struct ResourceGate: Sendable, Hashable {
    /// nil or 0: no limit.
    public var clicksLimit: Int?
    public var expirationURL: String
    public var sensitiveContent: Bool
    /// True when a password digest is stored.
    public private(set) var hasPassword: Bool

    /// Keys the gate owns. Typed settings leave them out of their `other`.
    public static let keys: Set<String> = [
        "clicks_limit", "expiration_url", "sensitive_content", "password", "password_hash",
    ]

    public init(clicksLimit: Int? = nil, expirationURL: String = "", sensitiveContent: Bool = false,
                hasPassword: Bool = false) {
        self.clicksLimit = clicksLimit
        self.expirationURL = expirationURL
        self.sensitiveContent = sensitiveContent
        self.hasPassword = hasPassword
    }

    /// Reads a stored settings object. `clicks_limit` arrives as a number
    /// from JSON writes and as a string from multipart ones.
    public init(json: [String: JSONValue]) {
        let limit = json["clicks_limit"]?.intValue
            ?? json["clicks_limit"]?.stringValue.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let sensitive: Bool
        switch json["sensitive_content"] {
        case .bool(let value): sensitive = value
        case .string(let value): sensitive = value == "true"
        default: sensitive = false
        }
        self.init(
            clicksLimit: (limit ?? 0) > 0 ? limit : nil,
            expirationURL: json["expiration_url"]?.stringValue ?? "",
            sensitiveContent: sensitive,
            hasPassword: !(json["password_hash"]?.stringValue ?? "").isEmpty
        )
    }

    /// Writes the gate into a JSON settings object that will replace the
    /// stored one: empty values are left out, the password per `password`.
    public func apply(to settings: inout [String: JSONValue], password: PasswordChange) {
        for key in Self.keys { settings[key] = nil }
        if let clicksLimit, clicksLimit > 0 { settings["clicks_limit"] = .int(clicksLimit) }
        let expiration = expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expiration.isEmpty { settings["expiration_url"] = .string(expiration) }
        settings["sensitive_content"] = .bool(sensitiveContent)
        switch password {
        case .keep: break
        case .set(let value): settings["password"] = .string(value)
        case .remove: settings["password"] = .string("")
        }
    }

    /// The multipart fields for a file link or static page.
    ///
    /// - Parameter saved: the stored gate on update, nil on create. A limit
    ///   removed since then is sent as `"0"` (no limit), because the server
    ///   ignores an empty value.
    public func formFields(password: PasswordChange, saved: ResourceGate?) -> [String: String] {
        var fields: [String: String] = ["sensitive_content": sensitiveContent ? "true" : "false"]
        if let clicksLimit, clicksLimit > 0 {
            fields["clicks_limit"] = String(clicksLimit)
        } else if saved?.clicksLimit != nil {
            fields["clicks_limit"] = "0"
        }
        let expiration = expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expiration.isEmpty { fields["expiration_url"] = expiration }
        switch password {
        case .keep: break
        case .set(let value): fields["password"] = value
        case .remove: fields["password"] = ""
        }
        return fields
    }
}

// MARK: - vCard

/// One phone number or social profile on a vCard: `{value}` or
/// `{label, value}`, with any other key kept.
public struct VCardEntry: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var label: String
    public var value: String
    public var other: [String: JSONValue]

    public init(id: UUID = UUID(), label: String = "", value: String = "", other: [String: JSONValue] = [:]) {
        self.id = id
        self.label = label
        self.value = value
        self.other = other.filter { $0.key != "label" && $0.key != "value" }
    }

    init(json: JSONValue) {
        if let object = json.objectValue {
            self.init(label: object["label"]?.stringValue ?? "", value: object["value"]?.stringValue ?? "", other: object)
        } else {
            self.init(value: json.stringValue ?? "")
        }
    }

    var json: JSONValue {
        var out = other
        out["value"] = .string(value.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty { out["label"] = .string(trimmedLabel) }
        return .object(out)
    }

    /// Two entries are the same content whatever their identity.
    public func sameContent(as other: VCardEntry) -> Bool {
        label == other.label && value == other.value && self.other == other.other
    }

    /// Entry identity is for SwiftUI lists only; equality is by content.
    public static func == (lhs: VCardEntry, rhs: VCardEntry) -> Bool { lhs.sameContent(as: rhs) }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(value)
        hasher.combine(other)
    }
}

/// A vCard's contact fields (`vcard_*`), plus every other stored key.
public struct VCardSettings: Sendable, Hashable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var website: String
    public var company: String
    public var jobTitle: String
    /// `YYYY-MM-DD` as the web stores it, or "".
    public var birthday: String
    public var street: String
    public var city: String
    public var zip: String
    public var region: String
    public var country: String
    public var note: String
    public var phoneNumbers: [VCardEntry]
    public var socials: [VCardEntry]
    /// Keys this type doesn't edit (gate keys excluded), written back unchanged.
    public var other: [String: JSONValue]

    static let editedKeys: Set<String> = [
        "vcard_first_name", "vcard_last_name", "vcard_email", "vcard_url", "vcard_company",
        "vcard_job_title", "vcard_birthday", "vcard_street", "vcard_city", "vcard_zip",
        "vcard_region", "vcard_country", "vcard_note", "vcard_phone_numbers", "vcard_socials",
    ]

    public init(firstName: String = "", lastName: String = "", email: String = "", website: String = "",
                company: String = "", jobTitle: String = "", birthday: String = "", street: String = "",
                city: String = "", zip: String = "", region: String = "", country: String = "", note: String = "",
                phoneNumbers: [VCardEntry] = [], socials: [VCardEntry] = [], other: [String: JSONValue] = [:]) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.website = website
        self.company = company
        self.jobTitle = jobTitle
        self.birthday = birthday
        self.street = street
        self.city = city
        self.zip = zip
        self.region = region
        self.country = country
        self.note = note
        self.phoneNumbers = phoneNumbers
        self.socials = socials
        self.other = other.filter { !Self.editedKeys.contains($0.key) && !ResourceGate.keys.contains($0.key) }
    }

    public init(json: [String: JSONValue]) {
        func string(_ key: String) -> String { json[key]?.stringValue ?? "" }
        func entries(_ key: String) -> [VCardEntry] { (json[key]?.arrayValue ?? []).map(VCardEntry.init(json:)) }
        self.init(
            firstName: string("vcard_first_name"), lastName: string("vcard_last_name"),
            email: string("vcard_email"), website: string("vcard_url"),
            company: string("vcard_company"), jobTitle: string("vcard_job_title"),
            birthday: string("vcard_birthday"), street: string("vcard_street"), city: string("vcard_city"),
            zip: string("vcard_zip"), region: string("vcard_region"), country: string("vcard_country"),
            note: string("vcard_note"),
            phoneNumbers: entries("vcard_phone_numbers"), socials: entries("vcard_socials"),
            other: json
        )
    }

    /// "Ada Lovelace", or "" when both names are empty.
    public var fullName: String {
        [firstName, lastName].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The `vcard_*` fields, trimmed, with blank list entries dropped.
    var fields: [String: JSONValue] {
        func trimmed(_ value: String) -> JSONValue { .string(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return [
            "vcard_first_name": trimmed(firstName), "vcard_last_name": trimmed(lastName),
            "vcard_email": trimmed(email), "vcard_url": trimmed(website),
            "vcard_company": trimmed(company), "vcard_job_title": trimmed(jobTitle),
            "vcard_birthday": trimmed(birthday), "vcard_street": trimmed(street),
            "vcard_city": trimmed(city), "vcard_zip": trimmed(zip), "vcard_region": trimmed(region),
            "vcard_country": trimmed(country), "vcard_note": .string(note),
            "vcard_phone_numbers": .array(phoneNumbers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.json)),
            "vcard_socials": .array(socials.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.json)),
        ]
    }

    /// The whole settings object for `PUT /vcards/{id}`.
    public func json(gate: ResourceGate, password: PasswordChange) -> [String: JSONValue] {
        var out = other
        for (key, value) in fields { out[key] = value }
        gate.apply(to: &out, password: password)
        return out
    }
}

/// What a vCard save sends.
public struct VCardDraft: Sendable, Hashable {
    public var slug: String
    /// Create only: the update handler ignores it.
    public var domainID: Int?
    public var card: VCardSettings
    public var gate: ResourceGate
    public var password: PasswordChange

    public init(slug: String, domainID: Int? = nil, card: VCardSettings, gate: ResourceGate = ResourceGate(),
                password: PasswordChange = .keep) {
        self.slug = slug
        self.domainID = domainID
        self.card = card
        self.gate = gate
        self.password = password
    }

    /// `POST /vcards`: the contact fields flat, everything else (the gate,
    /// kept keys) through the `settings` passthrough.
    var createBody: [String: JSONValue] {
        var body = card.fields
        body["url"] = .string(slug)
        if let domainID { body["domain_id"] = .int(domainID) }
        var extra = card.other
        gate.apply(to: &extra, password: password)
        body["settings"] = .object(extra)
        return body
    }

    /// `PUT /vcards/{id}`: the whole settings object.
    var updateBody: [String: JSONValue] {
        ["url": .string(slug), "settings": .object(card.json(gate: gate, password: password))]
    }
}

// MARK: - Event

/// An event's fields (`event_*`). Start, end and alerts are the author's
/// wall clock, `YYYY-MM-DDTHH:mm`, in ``timezone`` (ADR-0101): read them
/// with ``EventWallClock``, never as instants.
public struct EventSettings: Sendable, Hashable {
    public var name: String
    public var note: String
    /// A web page for the event (`event_url`).
    public var url: String
    public var location: String
    public var start: String
    public var end: String
    /// IANA zone name; the `.ics` uses it as the TZID.
    public var timezone: String
    /// Not edited by the web; kept as stored.
    public var firstAlert: String
    public var secondAlert: String
    public var other: [String: JSONValue]

    static let editedKeys: Set<String> = [
        "event_name", "event_note", "event_url", "event_location", "event_start_datetime",
        "event_end_datetime", "event_timezone", "event_first_alert_datetime", "event_second_alert_datetime",
    ]

    public init(name: String = "", note: String = "", url: String = "", location: String = "", start: String = "",
                end: String = "", timezone: String = "", firstAlert: String = "", secondAlert: String = "",
                other: [String: JSONValue] = [:]) {
        self.name = name
        self.note = note
        self.url = url
        self.location = location
        self.start = start
        self.end = end
        self.timezone = timezone
        self.firstAlert = firstAlert
        self.secondAlert = secondAlert
        self.other = other.filter { !Self.editedKeys.contains($0.key) && !ResourceGate.keys.contains($0.key) }
    }

    public init(json: [String: JSONValue]) {
        func string(_ key: String) -> String { json[key]?.stringValue ?? "" }
        self.init(name: string("event_name"), note: string("event_note"), url: string("event_url"),
                  location: string("event_location"), start: string("event_start_datetime"),
                  end: string("event_end_datetime"), timezone: string("event_timezone"),
                  firstAlert: string("event_first_alert_datetime"), secondAlert: string("event_second_alert_datetime"),
                  other: json)
    }

    var fields: [String: JSONValue] {
        func trimmed(_ value: String) -> JSONValue { .string(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return [
            "event_name": trimmed(name), "event_note": trimmed(note), "event_url": trimmed(url),
            "event_location": trimmed(location), "event_start_datetime": .string(start),
            "event_end_datetime": .string(end), "event_timezone": .string(timezone),
            "event_first_alert_datetime": .string(firstAlert), "event_second_alert_datetime": .string(secondAlert),
        ]
    }

    public func json(gate: ResourceGate, password: PasswordChange) -> [String: JSONValue] {
        var out = other
        for (key, value) in fields { out[key] = value }
        gate.apply(to: &out, password: password)
        return out
    }

    /// The start as an instant, when it and the zone parse.
    public var startDate: Date? { EventWallClock.date(from: start, timezone: timezone) }
    public var endDate: Date? { EventWallClock.date(from: end, timezone: timezone) }
}

/// What an event save sends.
public struct EventDraft: Sendable, Hashable {
    public var slug: String
    /// Create only (see the file header).
    public var domainID: Int?
    public var event: EventSettings
    public var gate: ResourceGate
    public var password: PasswordChange

    public init(slug: String, domainID: Int? = nil, event: EventSettings, gate: ResourceGate = ResourceGate(),
                password: PasswordChange = .keep) {
        self.slug = slug
        self.domainID = domainID
        self.event = event
        self.gate = gate
        self.password = password
    }

    /// `POST /events`: the event and gate fields flat (the handler reads
    /// `password`, `sensitive_content`, `clicks_limit` and `expiration_url`
    /// flat), kept keys through `settings`.
    var createBody: [String: JSONValue] {
        var body = event.fields
        body["url"] = .string(slug)
        if let domainID { body["domain_id"] = .int(domainID) }
        var gateFields: [String: JSONValue] = [:]
        gate.apply(to: &gateFields, password: password)
        for (key, value) in gateFields { body[key] = value }
        body["settings"] = .object(event.other)
        return body
    }

    var updateBody: [String: JSONValue] {
        ["url": .string(slug), "settings": .object(event.json(gate: gate, password: password))]
    }
}

/// The event wall-clock format, `YYYY-MM-DDTHH:mm` (an HTML
/// `datetime-local` value), converted in the event's own zone.
public enum EventWallClock {
    /// The instant a stored value names in `timezone` ("" or unknown: the
    /// device's zone). Accepts seconds and a trailing offset too.
    public static func date(from value: String, timezone: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let instant = CardsiteJSON.parseTimestamp(trimmed) { return instant }
        let zone = TimeZone(identifier: timezone) ?? .current
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            if let date = formatter(format, zone).date(from: trimmed) { return date }
        }
        return nil
    }

    /// `instant` as the wall clock in `timezone`, e.g. `2030-11-20T18:00`.
    public static func string(from instant: Date, timezone: String) -> String {
        formatter("yyyy-MM-dd'T'HH:mm", TimeZone(identifier: timezone) ?? .current).string(from: instant)
    }

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Payment link

/// A payment link's settings. The web sets none of its own; `title` is
/// what other clients (the contract run) set, shown when present.
public struct PaymentLinkSettings: Sendable, Hashable {
    public var title: String
    public var other: [String: JSONValue]

    public init(title: String = "", other: [String: JSONValue] = [:]) {
        self.title = title
        self.other = other.filter { $0.key != "title" && !ResourceGate.keys.contains($0.key) }
    }

    public init(json: [String: JSONValue]) {
        self.init(title: json["title"]?.stringValue ?? "", other: json)
    }

    public func json(gate: ResourceGate, password: PasswordChange) -> [String: JSONValue] {
        var out = other
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out["title"] = .string(trimmed) }
        gate.apply(to: &out, password: password)
        return out
    }
}

/// What a payment link save sends. Cardsite only redirects to the
/// checkout; the payment is taken by whoever hosts it.
public struct PaymentLinkDraft: Sendable, Hashable {
    public var slug: String
    /// Create only (see the file header).
    public var domainID: Int?
    /// Must start with `http://` or `https://` (422 otherwise).
    public var checkoutURL: String
    public var settings: PaymentLinkSettings
    public var gate: ResourceGate
    public var password: PasswordChange

    public init(slug: String, domainID: Int? = nil, checkoutURL: String, settings: PaymentLinkSettings = PaymentLinkSettings(),
                gate: ResourceGate = ResourceGate(), password: PasswordChange = .keep) {
        self.slug = slug
        self.domainID = domainID
        self.checkoutURL = checkoutURL
        self.settings = settings
        self.gate = gate
        self.password = password
    }

    var createBody: [String: JSONValue] {
        var body: [String: JSONValue] = [
            "url": .string(slug),
            "location_url": .string(checkoutURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            "settings": .object(settings.json(gate: gate, password: password)),
        ]
        if let domainID { body["domain_id"] = .int(domainID) }
        return body
    }

    var updateBody: [String: JSONValue] {
        [
            "url": .string(slug),
            "location_url": .string(checkoutURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            "settings": .object(settings.json(gate: gate, password: password)),
        ]
    }
}

// MARK: - File link

/// What the server stored for a file link (read-only).
public struct FileLinkSettings: Sendable, Hashable {
    /// The uploaded file's original name.
    public let fileName: String
    public let filePath: String
    public let forceDownload: Bool

    public init(fileName: String = "", filePath: String = "", forceDownload: Bool = false) {
        self.fileName = fileName
        self.filePath = filePath
        self.forceDownload = forceDownload
    }

    public init(json: [String: JSONValue]) {
        let force: Bool
        switch json["force_download_is_enabled"] {
        case .bool(let value): force = value
        case .string(let value): force = value == "true"
        default: force = false
        }
        self.init(fileName: json["file"]?.stringValue ?? "", filePath: json["file_path"]?.stringValue ?? "",
                  forceDownload: force)
    }
}

/// What a file link save sends (multipart).
public struct FileLinkDraft: Sendable, Hashable {
    public var slug: String
    /// Create only.
    public var domainID: Int?
    public var forceDownload: Bool
    public var gate: ResourceGate
    public var password: PasswordChange

    public init(slug: String, domainID: Int? = nil, forceDownload: Bool = false, gate: ResourceGate = ResourceGate(),
                password: PasswordChange = .keep) {
        self.slug = slug
        self.domainID = domainID
        self.forceDownload = forceDownload
        self.gate = gate
        self.password = password
    }

    func fields(saved: ResourceGate?) -> [String: String] {
        var fields = gate.formFields(password: password, saved: saved)
        fields["url"] = slug
        fields["force_download_is_enabled"] = forceDownload ? "true" : "false"
        if saved == nil, let domainID { fields["domain_id"] = String(domainID) }
        return fields
    }
}

// MARK: - Static page

/// What the server stored for a static page (read-only).
public struct StaticPageSettings: Sendable, Hashable {
    /// `html`, `markdown`, `svg` or `zip` (`staticKindFor`).
    public let kind: String
    public let folder: String
    public let filePath: String

    public init(kind: String = "", folder: String = "", filePath: String = "") {
        self.kind = kind
        self.folder = folder
        self.filePath = filePath
    }

    public init(json: [String: JSONValue]) {
        self.init(kind: json["static_kind"]?.stringValue ?? "", folder: json["static_folder"]?.stringValue ?? "",
                  filePath: json["file_path"]?.stringValue ?? "")
    }

    public var isSite: Bool { kind == "zip" }
}

/// What a static page save sends (multipart).
public struct StaticPageDraft: Sendable, Hashable {
    public var slug: String
    /// Create only.
    public var domainID: Int?
    public var gate: ResourceGate
    public var password: PasswordChange

    public init(slug: String, domainID: Int? = nil, gate: ResourceGate = ResourceGate(), password: PasswordChange = .keep) {
        self.slug = slug
        self.domainID = domainID
        self.gate = gate
        self.password = password
    }

    func fields(saved: ResourceGate?) -> [String: String] {
        var fields = gate.formFields(password: password, saved: saved)
        fields["url"] = slug
        if saved == nil, let domainID { fields["domain_id"] = String(domainID) }
        return fields
    }
}

/// What the file link and static page endpoints accept, checked on the
/// device before anything is sent.
public enum ResourceUploadRules {
    /// The per-file cap, `UploadRules.maxBytes` (10 MB).
    public static var maxBytes: Int64 { UploadRules.maxBytes }
    /// File links: `services.AllowedFileTypes`.
    public static var fileMIMETypes: Set<String> { UploadRules.fileMIMETypes }
    /// Static pages: an HTML page or a ZIP of a site. The server also takes
    /// Markdown and SVG (`allowedStaticTypes`).
    public static let staticMIMETypes: Set<String> = ["text/html", "application/zip", "text/markdown", "image/svg+xml"]
}

// MARK: - Splash page

/// A splash page (`/splash-pages`). Its own table: no address and no switch.
public struct SplashPage: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    public let name: String
    public let title: String
    public let description: String
    /// Seconds before the visitor may continue.
    public let linkUnlockSeconds: Int
    public let autoRedirect: Bool
    /// `secondary_button_name`, `secondary_button_url`, and the ads and
    /// custom code the app doesn't edit (the web never renders them).
    public let settings: [String: JSONValue]
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, title, description, settings
        case workspaceID = "workspace_id"
        case linkUnlockSeconds = "link_unlock_seconds"
        case autoRedirect = "auto_redirect"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, workspaceID: Int? = nil, name: String, title: String = "", description: String = "",
                linkUnlockSeconds: Int = 5, autoRedirect: Bool = false, settings: [String: JSONValue] = [:],
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.title = title
        self.description = description
        self.linkUnlockSeconds = linkUnlockSeconds
        self.autoRedirect = autoRedirect
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        linkUnlockSeconds = try c.decodeIfPresent(Int.self, forKey: .linkUnlockSeconds) ?? 5
        autoRedirect = try c.decodeIfPresent(Bool.self, forKey: .autoRedirect) ?? false
        settings = try c.decodeIfPresent(JSONValue.self, forKey: .settings)?.objectValue ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public var secondaryButtonName: String { settings["secondary_button_name"]?.stringValue ?? "" }
    public var secondaryButtonURL: String { settings["secondary_button_url"]?.stringValue ?? "" }

    /// The web's fallback order: name, title, `#id`.
    public var displayName: String {
        if !name.isEmpty { return name }
        if !title.isEmpty { return title }
        return "#\(id)"
    }
}

/// The Basic tab of a splash page, as one value to edit and send.
public struct SplashPageDraft: Sendable, Hashable {
    public var name: String
    public var title: String
    public var description: String
    public var linkUnlockSeconds: Int
    public var autoRedirect: Bool
    public var secondaryButtonName: String
    public var secondaryButtonURL: String
    /// Ads, custom CSS and JS: kept as stored, because `settings` is replaced.
    public var otherSettings: [String: JSONValue]

    public init(name: String = "", title: String = "", description: String = "", linkUnlockSeconds: Int = 5,
                autoRedirect: Bool = false, secondaryButtonName: String = "", secondaryButtonURL: String = "",
                otherSettings: [String: JSONValue] = [:]) {
        self.name = name
        self.title = title
        self.description = description
        self.linkUnlockSeconds = linkUnlockSeconds
        self.autoRedirect = autoRedirect
        self.secondaryButtonName = secondaryButtonName
        self.secondaryButtonURL = secondaryButtonURL
        self.otherSettings = otherSettings.filter { $0.key != "secondary_button_name" && $0.key != "secondary_button_url" }
    }

    public init(page: SplashPage) {
        self.init(name: page.name, title: page.title, description: page.description,
                  linkUnlockSeconds: page.linkUnlockSeconds, autoRedirect: page.autoRedirect,
                  secondaryButtonName: page.secondaryButtonName, secondaryButtonURL: page.secondaryButtonURL,
                  otherSettings: page.settings)
    }

    /// The body for create and update: every Basic field plus the whole
    /// `settings` object, empty values left out as the web does.
    var body: [String: JSONValue] {
        var settings = otherSettings
        let buttonName = secondaryButtonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let buttonURL = secondaryButtonURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !buttonName.isEmpty { settings["secondary_button_name"] = .string(buttonName) }
        if !buttonURL.isEmpty { settings["secondary_button_url"] = .string(buttonURL) }
        return [
            "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "link_unlock_seconds": .int(linkUnlockSeconds),
            "auto_redirect": .bool(autoRedirect),
            "settings": .object(settings),
        ]
    }
}
