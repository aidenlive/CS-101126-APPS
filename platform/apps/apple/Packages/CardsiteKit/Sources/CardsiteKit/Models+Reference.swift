import Foundation

// Reference data for resource editors: the targeting vocabulary (fixture
// 21k), the pickers' projects, domains and splash pages (21c, 21e, 21j),
// and the plan's capabilities (10a, 10b).
//
// The picker types are deliberately small "option" shapes: they decode only
// what a picker shows, so they never compete with the full Organise models.

// MARK: - Targeting

/// One choice in a targeting dimension, e.g. `{value: "GB", label: "United Kingdom"}`.
public struct TargetingOption: Codable, Sendable, Hashable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }

    enum CodingKeys: String, CodingKey {
        case value, label
    }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// `GET /reference/targeting`: the values the server's matcher understands,
/// derived from its own user-agent parser and ISO/CLDR.
public struct TargetingOptions: Decodable, Sendable, Hashable {
    public let browsers: [TargetingOption]
    public let continents: [TargetingOption]
    public let countries: [TargetingOption]
    public let deviceTypes: [TargetingOption]
    public let languages: [TargetingOption]
    public let operatingSystems: [TargetingOption]

    enum CodingKeys: String, CodingKey {
        case browsers, continents, countries, languages
        case deviceTypes = "device_types"
        case operatingSystems = "operating_systems"
    }

    public init(browsers: [TargetingOption] = [], continents: [TargetingOption] = [], countries: [TargetingOption] = [],
                deviceTypes: [TargetingOption] = [], languages: [TargetingOption] = [], operatingSystems: [TargetingOption] = []) {
        self.browsers = browsers
        self.continents = continents
        self.countries = countries
        self.deviceTypes = deviceTypes
        self.languages = languages
        self.operatingSystems = operatingSystems
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        browsers = try c.decodeIfPresent([TargetingOption].self, forKey: .browsers) ?? []
        continents = try c.decodeIfPresent([TargetingOption].self, forKey: .continents) ?? []
        countries = try c.decodeIfPresent([TargetingOption].self, forKey: .countries) ?? []
        deviceTypes = try c.decodeIfPresent([TargetingOption].self, forKey: .deviceTypes) ?? []
        languages = try c.decodeIfPresent([TargetingOption].self, forKey: .languages) ?? []
        operatingSystems = try c.decodeIfPresent([TargetingOption].self, forKey: .operatingSystems) ?? []
    }

    public func options(for dimension: DisplayRules.Dimension) -> [TargetingOption] {
        switch dimension {
        case .countries: return countries
        case .continents: return continents
        case .browsers: return browsers
        case .operatingSystems: return operatingSystems
        case .deviceTypes: return deviceTypes
        case .languages: return languages
        }
    }
}

// MARK: - Picker options

/// A project, for "file under" pickers.
public struct ProjectOption: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    /// `#3366ff`, as the user chose it.
    public let color: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color
    }

    public init(id: Int, name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// A custom domain, for address pickers.
public struct DomainOption: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// `https://` (the server stores the scheme with its separator).
    public let scheme: String
    public let host: String
    public let isEnabled: Bool
    public let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id, scheme, host
        case isEnabled = "is_enabled"
        case isVerified = "is_verified"
    }

    public init(id: Int, scheme: String = "https://", host: String, isEnabled: Bool = true, isVerified: Bool = true) {
        self.id = id
        self.scheme = scheme
        self.host = host
        self.isEnabled = isEnabled
        self.isVerified = isVerified
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        scheme = try c.decodeIfPresent(String.self, forKey: .scheme) ?? "https://"
        host = try c.decode(String.self, forKey: .host)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
    }

    /// Verified and switched on: the only domains an address can use.
    public var isUsable: Bool { isEnabled && isVerified }

    /// `https://go.example.com/slug`.
    public func url(for slug: String) -> URL? {
        let prefix = scheme.contains("://") ? scheme : scheme + "://"
        return URL(string: "\(prefix)\(host)/\(slug)")
    }
}

/// A splash page, for the link's "show first" picker.
public struct SplashPageOption: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let title: String?

    enum CodingKeys: String, CodingKey {
        case id, name, title
    }

    public init(id: Int, name: String, title: String? = nil) {
        self.id = id
        self.name = name
        self.title = title
    }

    /// The name, else the title, else `#id` (the web's fallback order).
    public var displayName: String {
        if !name.isEmpty { return name }
        if let title, !title.isEmpty { return title }
        return "#\(id)"
    }
}

// MARK: - Plan capabilities

/// What the account's plan includes (`apps/api/internal/models/capability.go`).
///
/// A capability key that is missing from the plan's settings is withheld,
/// not granted: the server's default for every key is `false`.
public struct PlanCapabilities: Sendable, Hashable {
    public static let targetingKey = "targeting_is_enabled"
    public static let passwordProtectionKey = "password_protection"

    public let settings: [String: JSONValue]

    public init(settings: [String: JSONValue]) {
        self.settings = settings
    }

    /// Everything included, for previews and for when the plan can't be read
    /// (the server still enforces every gate on write).
    public static let unrestricted = PlanCapabilities(settings: [
        targetingKey: true,
        passwordProtectionKey: true,
        "premium_blocks": true,
        "ai_tools": true,
        "api_is_enabled": true,
        "custom_pwa_is_enabled": true,
    ])

    public func includes(_ key: String) -> Bool {
        settings[key]?.boolValue ?? false
    }

    public var targeting: Bool { includes(Self.targetingKey) }
    public var passwordProtection: Bool { includes(Self.passwordProtectionKey) }
}
