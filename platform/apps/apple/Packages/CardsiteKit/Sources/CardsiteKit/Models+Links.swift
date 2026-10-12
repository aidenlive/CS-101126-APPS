import Foundation

// Short-link editor models, from fixtures 22a–22d (ContractTests/fixtures)
// and apps/api/internal/handlers/links.go.
//
// Server rules these types encode:
// - `PUT /links/{id}` REPLACES `settings`. ``LinkSettings`` keeps every key
//   it does not edit in ``LinkSettings/other`` and writes it back, so a save
//   from the app never drops a key the web set (cloaking JS and the like).
// - The stored password is a bcrypt digest under `settings.password_hash`.
//   It is never shown or sent back: its presence is ``LinkSettings/hasPassword``.
//   Saying nothing about `password` keeps it; `password: ""` removes it
//   (ADR-0083, services/link_password.go).
// - `project_id`, `domain_id` and `splash_page_id` sent as `null` detach;
//   left out, they are kept (ADR-0097).
// - `display_rules` that narrow the audience need the plan's
//   `targeting_is_enabled`; clearing them never does. Send them only when
//   they changed, so a link whose plan lost targeting can still be saved.
// - `scheduled_at` / `scheduled_end` sent as `null` are ignored by the
//   server (a nil `*time.Time` reads as "absent"), so a stored schedule can
//   be moved but not removed through this endpoint.

// MARK: - Link detail

/// A short link with everything the editor reads (`GET /links/{id}`).
public struct LinkDetail: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    public let type: String
    /// The address (`url` on the wire).
    public let slug: String
    /// Where it sends people (`location_url`).
    public let destination: String?
    public let projectID: Int?
    public let domainID: Int?
    public let splashPageID: Int?
    /// Decoded from the JSON-array-in-a-string the server sends (`"[3]"`).
    public let pixelIDs: [Int]
    public let settings: LinkSettings
    public let displayRules: DisplayRules
    /// IANA zone name, `""` when unset.
    public let timezone: String
    public let scheduledAt: Date?
    public let scheduledEnd: Date?
    public let clicks: Int
    public let isEnabled: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    public let lifecycleState: String?
    /// Present only once the address has been released: where what was here
    /// stays readable (track 009 phase 04).
    public let archiveURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, type, settings, timezone, clicks
        case workspaceID = "workspace_id"
        case slug = "url"
        case destination = "location_url"
        case projectID = "project_id"
        case domainID = "domain_id"
        case splashPageID = "splash_page_id"
        case pixelIDs = "pixels_ids"
        case displayRules = "display_rules"
        case scheduledAt = "scheduled_at"
        case scheduledEnd = "scheduled_end"
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lifecycleState = "lifecycle_state"
        case archiveURL = "archive_url"
    }

    public init(id: Int, workspaceID: Int? = nil, type: String = LinkKind.shortLink, slug: String,
                destination: String?, projectID: Int? = nil, domainID: Int? = nil, splashPageID: Int? = nil,
                pixelIDs: [Int] = [], settings: LinkSettings = LinkSettings(), displayRules: DisplayRules = DisplayRules(),
                timezone: String = "", scheduledAt: Date? = nil, scheduledEnd: Date? = nil, clicks: Int = 0,
                isEnabled: Bool = true, createdAt: Date? = nil, updatedAt: Date? = nil,
                lifecycleState: String? = "active", archiveURL: URL? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.type = type
        self.slug = slug
        self.destination = destination
        self.projectID = projectID
        self.domainID = domainID
        self.splashPageID = splashPageID
        self.pixelIDs = pixelIDs
        self.settings = settings
        self.displayRules = displayRules
        self.timezone = timezone
        self.scheduledAt = scheduledAt
        self.scheduledEnd = scheduledEnd
        self.clicks = clicks
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lifecycleState = lifecycleState
        self.archiveURL = archiveURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? LinkKind.shortLink
        slug = try c.decode(String.self, forKey: .slug)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        projectID = try c.decodeIfPresent(Int.self, forKey: .projectID)
        domainID = try c.decodeIfPresent(Int.self, forKey: .domainID)
        splashPageID = try c.decodeIfPresent(Int.self, forKey: .splashPageID)
        pixelIDs = Self.decodePixelIDs(try c.decodeIfPresent(JSONValue.self, forKey: .pixelIDs))
        let settingsObject = try c.decodeIfPresent(JSONValue.self, forKey: .settings)?.objectValue ?? [:]
        settings = LinkSettings(json: settingsObject)
        let rulesObject = try c.decodeIfPresent(JSONValue.self, forKey: .displayRules)?.objectValue ?? [:]
        displayRules = DisplayRules(json: rulesObject)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? ""
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        scheduledEnd = try c.decodeIfPresent(Date.self, forKey: .scheduledEnd)
        clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        lifecycleState = try c.decodeIfPresent(String.self, forKey: .lifecycleState)
        archiveURL = try c.decodeIfPresent(String.self, forKey: .archiveURL).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// `"[3]"` (what the server sends), `[3]`, or nothing.
    static func decodePixelIDs(_ value: JSONValue?) -> [Int] {
        switch value {
        case .array(let items):
            return items.compactMap(\.intValue)
        case .string(let raw):
            guard let data = raw.data(using: .utf8),
                  let items = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
            return items
        default:
            return []
        }
    }

    /// The list-row shape, for updating a list after a save.
    public var resource: Resource {
        Resource(id: id, workspaceID: workspaceID, type: type, slug: slug, destination: destination,
                 clicks: clicks, isEnabled: isEnabled, createdAt: createdAt, updatedAt: updatedAt,
                 lifecycleState: lifecycleState)
    }

    public var isLapsing: Bool { resource.isLapsing }
}

// MARK: - Settings

/// HTTP status a short link redirects with.
public enum RedirectStatus: Int, CaseIterable, Sendable, Hashable, Identifiable {
    case permanent = 301
    case temporary = 302
    case temporaryPreservingMethod = 307

    public var id: Int { rawValue }
}

/// What a save does to the gate password.
public enum PasswordChange: Sendable, Hashable {
    /// Say nothing: the server keeps the stored digest.
    case keep
    /// Set or replace it.
    case set(String)
    /// Remove it (`password: ""`).
    case remove
}

/// The editable keys of a link's `settings`, plus every other key as stored.
public struct LinkSettings: Sendable, Hashable {
    public var clicksLimit: Int?
    public var expirationURL: String
    public var sensitiveContent: Bool
    public var cloakingEnabled: Bool
    public var cloakingTitle: String
    public var cloakingMetaDescription: String
    public var redirectStatus: RedirectStatus
    public var forwardQueryParameters: Bool
    public var utmSource: String
    public var utmMedium: String
    public var utmCampaign: String
    /// True when the link has a stored password digest.
    public private(set) var hasPassword: Bool
    /// Keys this type does not edit, written back unchanged. Never holds
    /// `password` or `password_hash`.
    public var other: [String: JSONValue]

    static let editedKeys: Set<String> = [
        "clicks_limit", "expiration_url", "sensitive_content", "cloaking_is_enabled", "cloaking_title",
        "cloaking_meta_description", "http_status_code", "forward_query_parameters_is_enabled",
        "utm_source", "utm_medium", "utm_campaign", "password", "password_hash",
    ]

    public init(clicksLimit: Int? = nil, expirationURL: String = "", sensitiveContent: Bool = false,
                cloakingEnabled: Bool = false, cloakingTitle: String = "", cloakingMetaDescription: String = "",
                redirectStatus: RedirectStatus = .temporary, forwardQueryParameters: Bool = false,
                utmSource: String = "", utmMedium: String = "", utmCampaign: String = "",
                hasPassword: Bool = false, other: [String: JSONValue] = [:]) {
        self.clicksLimit = clicksLimit
        self.expirationURL = expirationURL
        self.sensitiveContent = sensitiveContent
        self.cloakingEnabled = cloakingEnabled
        self.cloakingTitle = cloakingTitle
        self.cloakingMetaDescription = cloakingMetaDescription
        self.redirectStatus = redirectStatus
        self.forwardQueryParameters = forwardQueryParameters
        self.utmSource = utmSource
        self.utmMedium = utmMedium
        self.utmCampaign = utmCampaign
        self.hasPassword = hasPassword
        self.other = other.filter { !Self.editedKeys.contains($0.key) }
    }

    /// Reads a stored `settings` object.
    public init(json: [String: JSONValue]) {
        func string(_ key: String) -> String { json[key]?.stringValue ?? "" }
        func bool(_ key: String) -> Bool { json[key]?.boolValue ?? false }
        let status = json["http_status_code"]?.intValue ?? Int(string("http_status_code"))
        self.init(
            clicksLimit: json["clicks_limit"]?.intValue ?? Int(string("clicks_limit")),
            expirationURL: string("expiration_url"),
            sensitiveContent: bool("sensitive_content"),
            cloakingEnabled: bool("cloaking_is_enabled"),
            cloakingTitle: string("cloaking_title"),
            cloakingMetaDescription: string("cloaking_meta_description"),
            redirectStatus: status.flatMap(RedirectStatus.init(rawValue:)) ?? .temporary,
            forwardQueryParameters: bool("forward_query_parameters_is_enabled"),
            utmSource: string("utm_source"),
            utmMedium: string("utm_medium"),
            utmCampaign: string("utm_campaign"),
            hasPassword: !(json["password_hash"]?.stringValue ?? "").isEmpty,
            other: json
        )
    }

    /// The whole object to send, shaped as the web's `linkPayloadFromForm`:
    /// empty values are left out, cloaking text only goes with cloaking on.
    public func json(password: PasswordChange) -> [String: JSONValue] {
        var out = other
        if let clicksLimit, clicksLimit > 0 { out["clicks_limit"] = .int(clicksLimit) }
        let expiration = expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expiration.isEmpty { out["expiration_url"] = .string(expiration) }
        if sensitiveContent { out["sensitive_content"] = .bool(true) }
        if cloakingEnabled {
            out["cloaking_is_enabled"] = .bool(true)
            if !cloakingTitle.isEmpty { out["cloaking_title"] = .string(cloakingTitle) }
            if !cloakingMetaDescription.isEmpty { out["cloaking_meta_description"] = .string(cloakingMetaDescription) }
        }
        out["http_status_code"] = .int(redirectStatus.rawValue)
        if forwardQueryParameters { out["forward_query_parameters_is_enabled"] = .bool(true) }
        if !utmSource.isEmpty { out["utm_source"] = .string(utmSource) }
        if !utmMedium.isEmpty { out["utm_medium"] = .string(utmMedium) }
        if !utmCampaign.isEmpty { out["utm_campaign"] = .string(utmCampaign) }
        switch password {
        case .keep: break
        case .set(let value): out["password"] = .string(value)
        case .remove: out["password"] = .string("")
        }
        return out
    }
}

// MARK: - Display rules

/// Audience targeting (`display_rules`). Shared by links, bio pages and blocks.
///
/// The six dimensions match the keys of `GET /reference/targeting`. Any
/// other key (`cities`, or schedule keys some clients store here) is kept in
/// ``other`` and written back unchanged.
public struct DisplayRules: Sendable, Hashable {
    public enum Dimension: String, CaseIterable, Sendable, Hashable, Identifiable {
        case countries
        case continents
        case browsers
        case operatingSystems = "operating_systems"
        case deviceTypes = "device_types"
        case languages

        public var id: String { rawValue }
    }

    private var values: [Dimension: [String]]
    public var other: [String: JSONValue]

    public init(_ values: [Dimension: [String]] = [:], other: [String: JSONValue] = [:]) {
        self.values = values.filter { !$0.value.isEmpty }
        self.other = other.filter { key, _ in Dimension(rawValue: key) == nil }
    }

    public init(json: [String: JSONValue]) {
        var values: [Dimension: [String]] = [:]
        for dimension in Dimension.allCases {
            let items = json[dimension.rawValue]?.arrayValue?.compactMap(\.stringValue) ?? []
            if !items.isEmpty { values[dimension] = items }
        }
        self.init(values, other: json)
    }

    /// The selected values, in stored order. Setting `[]` clears the dimension.
    public subscript(dimension: Dimension) -> [String] {
        get { values[dimension] ?? [] }
        set { values[dimension] = newValue.isEmpty ? nil : newValue }
    }

    /// True when any dimension (including `cities` in ``other``) limits who sees it.
    public var narrowsAudience: Bool {
        if values.values.contains(where: { !$0.isEmpty }) { return true }
        return !(other["cities"]?.arrayValue ?? []).isEmpty
    }

    public var isEmpty: Bool { !narrowsAudience }

    public var json: [String: JSONValue] {
        var out = other
        for (dimension, items) in values where !items.isEmpty {
            out[dimension.rawValue] = .array(items.map(JSONValue.string))
        }
        return out
    }
}

// MARK: - Save request

/// A full `PUT /links/{id}` body built from editor state.
public struct LinkChanges: Sendable, Hashable {
    public var slug: String
    public var destination: String
    public var domainID: Int?
    public var projectID: Int?
    public var splashPageID: Int?
    public var settings: LinkSettings
    public var password: PasswordChange
    /// nil leaves the stored rules alone (and skips the targeting gate).
    public var displayRules: DisplayRules?
    public var timezone: String
    /// nil says nothing (the server keeps what it has).
    public var scheduledAt: Date?
    public var scheduledEnd: Date?

    public init(slug: String, destination: String, domainID: Int?, projectID: Int?, splashPageID: Int?,
                settings: LinkSettings, password: PasswordChange = .keep, displayRules: DisplayRules?,
                timezone: String, scheduledAt: Date?, scheduledEnd: Date?) {
        self.slug = slug
        self.destination = destination
        self.domainID = domainID
        self.projectID = projectID
        self.splashPageID = splashPageID
        self.settings = settings
        self.password = password
        self.displayRules = displayRules
        self.timezone = timezone
        self.scheduledAt = scheduledAt
        self.scheduledEnd = scheduledEnd
    }

    /// The JSON body. `settings` is always the whole object, because the
    /// server replaces it.
    public var body: [String: JSONValue] {
        func reference(_ id: Int?) -> JSONValue { id.map(JSONValue.int) ?? .null }
        var body: [String: JSONValue] = [
            "url": .string(slug),
            "location_url": .string(destination),
            "domain_id": reference(domainID),
            "project_id": reference(projectID),
            "splash_page_id": reference(splashPageID),
            "settings": .object(settings.json(password: password)),
            "timezone": .string(timezone),
        ]
        if let displayRules { body["display_rules"] = .object(displayRules.json) }
        if let scheduledAt { body["scheduled_at"] = .string(Self.timestamp(scheduledAt)) }
        if let scheduledEnd { body["scheduled_end"] = .string(Self.timestamp(scheduledEnd)) }
        return body
    }

    /// RFC 3339 in UTC, which Go's `time.Time` decodes.
    static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC") ?? .gmt))
    }
}
