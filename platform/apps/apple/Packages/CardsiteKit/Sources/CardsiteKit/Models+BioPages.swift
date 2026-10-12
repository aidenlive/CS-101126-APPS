import Foundation

// Bio pages and their blocks, as observed by ContractTests/native-contract.sh
// (fixtures 09, 24a–24j, 21f–21h) and the Go handlers in
// apps/api/internal/handlers/biolinks.go and biolink_blocks.go.
//
// Uploads, the targeting vocabulary and plan capabilities come from the
// shared models (`UploadItem`, `TargetingOptions`, `PlanCapabilities`).
// Pixels carry a `Bio` prefix so this file can land beside a fuller
// Organise model without a clash.

// MARK: - Bio page

/// A bio page: a `links` row with `type: "biolink"`. Its look and header live
/// in `settings`, which a PUT replaces whole.
public struct BioPage: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    /// The address (`url` on the wire).
    public var slug: String
    public var settings: [String: JSONValue]
    public let clicks: Int
    public var isEnabled: Bool
    /// Listed in the public directory. Only trust the value from
    /// `GET /biolinks/{id}` or a PUT: the list endpoint always sends `false`
    /// (ContractTests quirk 3).
    public var directoryIsEnabled: Bool
    public var displayRules: [String: JSONValue]
    /// Pixels the public page emits. The server sends a JSON array inside a
    /// string (`"[2]"`, quirk 4); this is the parsed list.
    public var pixelIDs: [Int]
    public var timezone: String?
    public let domainID: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let lifecycleState: String?

    enum CodingKeys: String, CodingKey {
        case id, settings, clicks, timezone
        case workspaceID = "workspace_id"
        case slug = "url"
        case isEnabled = "is_enabled"
        case directoryIsEnabled = "directory_is_enabled"
        case displayRules = "display_rules"
        case pixelIDs = "pixels_ids"
        case domainID = "domain_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lifecycleState = "lifecycle_state"
    }

    public init(id: Int, workspaceID: Int? = nil, slug: String, settings: [String: JSONValue] = [:],
                clicks: Int = 0, isEnabled: Bool = true, directoryIsEnabled: Bool = true,
                displayRules: [String: JSONValue] = [:], pixelIDs: [Int] = [], timezone: String? = nil,
                domainID: Int? = nil, createdAt: Date? = nil, updatedAt: Date? = nil,
                lifecycleState: String? = "active") {
        self.id = id
        self.workspaceID = workspaceID
        self.slug = slug
        self.settings = settings
        self.clicks = clicks
        self.isEnabled = isEnabled
        self.directoryIsEnabled = directoryIsEnabled
        self.displayRules = displayRules
        self.pixelIDs = pixelIDs
        self.timezone = timezone
        self.domainID = domainID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lifecycleState = lifecycleState
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        slug = try c.decode(String.self, forKey: .slug)
        settings = try c.decodeIfPresent(JSONValue.self, forKey: .settings)?.objectValue ?? [:]
        clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        directoryIsEnabled = try c.decodeIfPresent(Bool.self, forKey: .directoryIsEnabled) ?? true
        displayRules = try c.decodeIfPresent(JSONValue.self, forKey: .displayRules)?.objectValue ?? [:]
        pixelIDs = Self.decodePixelIDs(from: c)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        domainID = try c.decodeIfPresent(Int.self, forKey: .domainID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        lifecycleState = try c.decodeIfPresent(String.self, forKey: .lifecycleState)
    }

    /// `"[2,5]"` (what the server sends), `[2,5]`, or absent.
    private static func decodePixelIDs(from c: KeyedDecodingContainer<CodingKeys>) -> [Int] {
        if let list = try? c.decodeIfPresent([Int].self, forKey: .pixelIDs) {
            return list
        }
        guard let raw = try? c.decodeIfPresent(String.self, forKey: .pixelIDs),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([JSONValue].self, from: data) else {
            return []
        }
        return parsed.compactMap(\.intValue)
    }

    /// The name shown at the top of the page (`settings.title`), if set.
    public var title: String? {
        guard let value = settings["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// Same rule as ``Resource/isLapsing``.
    public var isLapsing: Bool {
        guard let lifecycleState, !lifecycleState.isEmpty else { return false }
        return lifecycleState != "active"
    }
}

/// `GET /biolinks/{id}`: the page and up to 100 of its blocks, in order.
public struct BioPageDocument: Decodable, Sendable, Hashable {
    public var page: BioPage
    public var blocks: [BioBlock]

    enum CodingKeys: String, CodingKey {
        case page = "biolink"
        case blocks
    }

    public init(page: BioPage, blocks: [BioBlock]) {
        self.page = page
        self.blocks = blocks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decode(BioPage.self, forKey: .page)
        let blocks = try c.decodeIfPresent([BioBlock].self, forKey: .blocks) ?? []
        // The server already orders by `order`; sorting again (stably) keeps
        // a reordered page right if that ever changes.
        self.blocks = blocks.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }
}

/// Partial update for `PUT /biolinks/{id}`. Fields left nil are not sent and
/// stay as stored. `settings` replaces the stored object whole, so pass the
/// complete object.
public struct BioPageChanges: Sendable, Equatable {
    public var slug: String?
    public var settings: [String: JSONValue]?
    public var displayRules: [String: JSONValue]?
    /// An empty list detaches every pixel.
    public var pixelIDs: [Int]?
    public var isEnabled: Bool?
    public var directoryIsEnabled: Bool?

    public init(slug: String? = nil, settings: [String: JSONValue]? = nil, displayRules: [String: JSONValue]? = nil,
                pixelIDs: [Int]? = nil, isEnabled: Bool? = nil, directoryIsEnabled: Bool? = nil) {
        self.slug = slug
        self.settings = settings
        self.displayRules = displayRules
        self.pixelIDs = pixelIDs
        self.isEnabled = isEnabled
        self.directoryIsEnabled = directoryIsEnabled
    }

    var body: [String: JSONValue] {
        var body: [String: JSONValue] = [:]
        if let slug { body["url"] = .string(slug) }
        if let settings { body["settings"] = .object(settings) }
        if let displayRules { body["display_rules"] = .object(displayRules) }
        if let pixelIDs { body["pixels_ids"] = .array(pixelIDs.map { .int($0) }) }
        if let isEnabled { body["is_enabled"] = .bool(isEnabled) }
        if let directoryIsEnabled { body["directory_is_enabled"] = .bool(directoryIsEnabled) }
        return body
    }
}

// MARK: - Blocks

/// One block on a bio page. `location_url` is a column of its own, not a
/// settings key, even though the type's field list names it.
public struct BioBlock: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let linkID: Int
    public let type: String
    public var locationURL: String?
    public var settings: [String: JSONValue]
    public let clicks: Int
    public var isEnabled: Bool
    public var order: Int
    /// Sent back on every PUT; a stale one gets a 409 (``BlockConflictError``).
    public var version: Int
    public let lastEditorUserID: Int?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, settings, clicks, order, version
        case linkID = "link_id"
        case locationURL = "location_url"
        case isEnabled = "is_enabled"
        case lastEditorUserID = "last_editor_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, linkID: Int, type: String, locationURL: String? = nil, settings: [String: JSONValue] = [:],
                clicks: Int = 0, isEnabled: Bool = true, order: Int = 0, version: Int = 1,
                lastEditorUserID: Int? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.linkID = linkID
        self.type = type
        self.locationURL = locationURL
        self.settings = settings
        self.clicks = clicks
        self.isEnabled = isEnabled
        self.order = order
        self.version = version
        self.lastEditorUserID = lastEditorUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        linkID = try c.decodeIfPresent(Int.self, forKey: .linkID) ?? 0
        type = try c.decode(String.self, forKey: .type)
        locationURL = try c.decodeIfPresent(String.self, forKey: .locationURL)
        settings = try c.decodeIfPresent(JSONValue.self, forKey: .settings)?.objectValue ?? [:]
        clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        lastEditorUserID = try c.decodeIfPresent(Int.self, forKey: .lastEditorUserID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// `GET /biolink-blocks/types`: one entry per block type (85 today), with
/// the field specs an inspector is generated from.
public struct BlockType: Decodable, Sendable, Hashable, Identifiable {
    public static let premiumCapability = "premium_blocks"

    public let type: String
    public let name: String
    /// `standard`, `forms`, `advanced`, `embeds` or `payments`.
    public let category: String
    /// A Font Awesome class (`fas fa-link`); the app maps types to SF Symbols.
    public let icon: String?
    /// `#rrggbb`.
    public let color: String?
    public let hasStatistics: Bool
    /// The plan capability adding this type needs, when it needs one.
    public let capability: String?
    public let fields: [BlockField]

    public var id: String { type }
    public var isPremium: Bool { capability == Self.premiumCapability }

    enum CodingKeys: String, CodingKey {
        case type, name, category, icon, color, capability, fields
        case hasStatistics = "has_statistics"
    }

    public init(type: String, name: String, category: String, icon: String? = nil, color: String? = nil,
                hasStatistics: Bool = false, capability: String? = nil, fields: [BlockField] = []) {
        self.type = type
        self.name = name
        self.category = category
        self.icon = icon
        self.color = color
        self.hasStatistics = hasStatistics
        self.capability = capability
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? type
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "standard"
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        hasStatistics = try c.decodeIfPresent(Bool.self, forKey: .hasStatistics) ?? false
        capability = try c.decodeIfPresent(String.self, forKey: .capability)
        fields = try c.decodeIfPresent([BlockField].self, forKey: .fields) ?? []
    }
}

public struct BlockField: Decodable, Sendable, Hashable, Identifiable {
    public let name: String
    /// The wire kind (`text`, `url`, `markers-list`, …). See ``fieldKind``.
    public let kind: String
    public let label: String
    public let options: [BlockFieldOption]

    public var id: String { name }
    public var fieldKind: BlockFieldKind { BlockFieldKind(wire: kind) }

    enum CodingKeys: String, CodingKey {
        case name, kind, label, options
    }

    public init(name: String, kind: String, label: String, options: [BlockFieldOption] = []) {
        self.name = name
        self.kind = kind
        self.label = label
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? name
        options = try c.decodeIfPresent([BlockFieldOption].self, forKey: .options) ?? []
    }
}

public struct BlockFieldOption: Decodable, Sendable, Hashable, Identifiable {
    /// Always a string here, whatever JSON type the server used.
    public let value: String
    public let label: String

    public var id: String { value }

    enum CodingKeys: String, CodingKey { case value, label }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(JSONValue.self, forKey: .value)
        value = raw.displayString
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? value
    }
}

/// The field kinds the block registry uses. The last case covers the
/// structured kinds the web edits as raw JSON (`markers-list`, `times-grid`,
/// `socials-map`, `notifications-picker`, `payment-processors-picker`) and
/// any kind added later.
public enum BlockFieldKind: Sendable, Hashable {
    case text, url, textarea, richText, number, boolean, select, multiSelect
    case color, dateTime, timeZone, image, file, code, embed
    case structured(String)

    public init(wire: String) {
        switch wire {
        case "text": self = .text
        case "url": self = .url
        case "textarea": self = .textarea
        case "richtext": self = .richText
        case "number": self = .number
        case "boolean": self = .boolean
        case "select": self = .select
        case "multiselect": self = .multiSelect
        case "color": self = .color
        case "datetime": self = .dateTime
        case "timezone": self = .timeZone
        case "image": self = .image
        case "file": self = .file
        case "code": self = .code
        case "embed": self = .embed
        default: self = .structured(wire)
        }
    }
}

/// A block PUT lost to someone else's write (409). `lastEditorName` is the
/// workspace member who saved last, when the server could name them.
public struct BlockConflictError: Error, Sendable, Equatable {
    public let lastEditorName: String?

    public init(lastEditorName: String?) {
        self.lastEditorName = lastEditorName
    }

    /// Reads the name out of the 409 title, which is
    /// `"<name> changed this block — reload it and reapply your change"`, or
    /// `"Block was modified elsewhere — …"` when nobody can be named.
    ///
    /// The name also travels as `error.last_editor.name`; the shared error
    /// envelope does not decode that yet, so the title is the source here.
    init(serverTitle: String) {
        let marker = " changed this block"
        if let range = serverTitle.range(of: marker) {
            let name = serverTitle[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            lastEditorName = name.isEmpty ? nil : name
        } else {
            lastEditorName = nil
        }
    }
}

extension BlockConflictError: LocalizedError {
    public var errorDescription: String? {
        if let lastEditorName {
            return String(localized: "\(lastEditorName) changed this block. Reload it, then reapply your edit.")
        }
        return String(localized: "This block changed elsewhere. Reload it, then reapply your edit.")
    }
}

// MARK: - Pixels

/// `GET /pixels` row.
public struct BioPixel: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// The provider key, matching ``BioPixelType/key``.
    public let type: String
    public let name: String

    enum CodingKeys: String, CodingKey { case id, type, name }

    public init(id: Int, type: String, name: String) {
        self.id = id
        self.type = type
        self.name = name
    }
}

/// `GET /pixels/types` row.
public struct BioPixelType: Decodable, Sendable, Hashable, Identifiable {
    public let key: String
    public let name: String
    /// Whether a bio page can emit this provider at all: only providers with
    /// a no-script beacon can (ADR-0096).
    public let emitsBeacon: Bool

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name
        case emitsBeacon = "emits_beacon"
    }

    public init(key: String, name: String, emitsBeacon: Bool) {
        self.key = key
        self.name = name
        self.emitsBeacon = emitsBeacon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? key
        emitsBeacon = try c.decodeIfPresent(Bool.self, forKey: .emitsBeacon) ?? false
    }
}

// MARK: - JSONValue display

public extension JSONValue {
    /// A plain-text rendering for labels and text fields: strings as they
    /// are, numbers without a trailing `.0`, booleans as `true`/`false`, and
    /// an empty string for null, arrays and objects.
    var displayString: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value):
            if let whole = Int(exactly: value) { return String(whole) }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null, .array, .object: return ""
        }
    }
}
