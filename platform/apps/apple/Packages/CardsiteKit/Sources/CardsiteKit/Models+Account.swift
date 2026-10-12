import Foundation

// Account security, API tokens and preferences. Shapes from fixtures 26a–26r
// and the Go handlers (account.go, account_tokens.go, auth.go,
// auth_recovery.go).

// MARK: - Two-factor authentication

/// `POST /auth/2fa/setup`. The secret is pending until a code is verified.
public struct TwoFactorSetup: Codable, Sendable, Hashable {
    /// Base32 TOTP secret, for typing into an authenticator by hand.
    public let secret: String
    /// `otpauth://totp/…`, what the QR code encodes.
    public let provisioningURL: String

    enum CodingKeys: String, CodingKey {
        case secret
        case provisioningURL = "provisioning_url"
    }

    public init(secret: String, provisioningURL: String) {
        self.secret = secret
        self.provisioningURL = provisioningURL
    }
}

/// `GET /auth/2fa/recovery-codes`. The source of truth for whether 2FA is
/// on: `GET /user` is cached for about 10 minutes and the sign-in response
/// reports `twofa_enabled:false` even after a recovery-code sign-in.
public struct TwoFactorStatus: Codable, Sendable, Hashable {
    public let isEnabled: Bool
    /// Unused recovery codes left (0 when 2FA is off).
    public let remainingRecoveryCodes: Int

    enum CodingKeys: String, CodingKey {
        case isEnabled = "twofa_enabled"
        case remainingRecoveryCodes = "remaining"
    }

    public init(isEnabled: Bool, remainingRecoveryCodes: Int) {
        self.isEnabled = isEnabled
        self.remainingRecoveryCodes = remainingRecoveryCodes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        remainingRecoveryCodes = try c.decodeIfPresent(Int.self, forKey: .remainingRecoveryCodes) ?? 0
    }
}

/// `{recovery_codes:[String]}` from `POST /auth/2fa/verify` and
/// `POST /auth/2fa/recovery-codes`. Shown once; only hashes are stored.
struct RecoveryCodesPayload: Decodable {
    let recoveryCodes: [String]?

    enum CodingKeys: String, CodingKey {
        case recoveryCodes = "recovery_codes"
    }
}

// MARK: - API tokens

/// A scoped, revocable API token (`GET /account/tokens`). The secret is
/// never listed; it exists only in ``CreatedAPIToken``.
public struct APIToken: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let scopes: [String]
    public let lastUsedAt: Date?
    public let expiresAt: Date?
    public let revokedAt: Date?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, scopes
        case lastUsedAt = "last_used_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case createdAt = "created_at"
    }

    public init(id: Int, name: String, scopes: [String], lastUsedAt: Date? = nil, expiresAt: Date? = nil,
                revokedAt: Date? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.scopes = scopes
        self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        revokedAt = try c.decodeIfPresent(Date.self, forKey: .revokedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    public enum Status: Sendable, Hashable {
        case active, expired, revoked
    }

    public func status(at now: Date = Date()) -> Status {
        if revokedAt != nil { return .revoked }
        if let expiresAt, expiresAt <= now { return .expired }
        return .active
    }
}

/// `GET /account/tokens`: an object, not a list.
public struct APITokenList: Codable, Sendable, Hashable {
    /// Every scope the server knows, for the create form.
    public let scopes: [String]
    /// Revoked tokens included, newest first as the server sends them.
    public let tokens: [APIToken]

    enum CodingKeys: String, CodingKey {
        case scopes, tokens
    }

    public init(scopes: [String], tokens: [APIToken]) {
        self.scopes = scopes
        self.tokens = tokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        tokens = try c.decodeIfPresent([APIToken].self, forKey: .tokens) ?? []
    }
}

/// `POST /account/tokens` (201). `secret` (`cst_…`) is shown once.
public struct CreatedAPIToken: Codable, Sendable, Hashable {
    public let token: APIToken
    public let secret: String
    public let notice: String?

    enum CodingKeys: String, CodingKey {
        case token, secret, notice
    }

    public init(token: APIToken, secret: String, notice: String? = nil) {
        self.token = token
        self.secret = secret
        self.notice = notice
    }
}

// MARK: - Preferences

/// `GET/PUT /account/preferences`: a free-form object (`{}` when never set).
///
/// The PUT **replaces** the stored object, so this keeps every key the
/// server sent — including the ones the app does not edit (OpenAI key,
/// white-label settings) — and sends them all back.
public struct AccountPreferences: Codable, Sendable, Hashable {
    public var values: [String: JSONValue]

    public init(_ values: [String: JSONValue] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            values = [:]
        } else {
            values = try container.decode([String: JSONValue].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public subscript(key: String) -> JSONValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    // Keys as the web's PreferencesPage writes them.
    public enum Key {
        public static let resultsPerPage = "default_results_per_page"
        public static let orderType = "default_order_type"
        public static let autoCopyLink = "links_auto_copy_link"
        public static let autoSaveLinkSettings = "links_autosave_settings"
        public static let excludedIPs = "excluded_ips"
        public static let linksOrderBy = "links_default_order_by"
        public static let biolinksOrderBy = "biolinks_default_order_by"
        public static let qrCodesOrderBy = "qr_codes_default_order_by"
        public static let pixelsOrderBy = "pixels_default_order_by"
        public static let projectsOrderBy = "projects_default_order_by"
        public static let domainsOrderBy = "domains_default_order_by"
    }

    /// 10, 25, 50 or 100; 25 when unset. Accepts a number sent as a string.
    public var resultsPerPage: Int {
        get { values[Key.resultsPerPage]?.intValue ?? values[Key.resultsPerPage]?.stringValue.flatMap(Int.init) ?? 25 }
        set { values[Key.resultsPerPage] = .int(newValue) }
    }

    /// `"ASC"` or `"DESC"`; `"DESC"` when unset.
    public var orderType: String {
        get { values[Key.orderType]?.stringValue ?? "DESC" }
        set { values[Key.orderType] = .string(newValue) }
    }

    public var autoCopyLink: Bool {
        get { values[Key.autoCopyLink]?.boolValue ?? false }
        set { values[Key.autoCopyLink] = .bool(newValue) }
    }

    public var autoSaveLinkSettings: Bool {
        get { values[Key.autoSaveLinkSettings]?.boolValue ?? false }
        set { values[Key.autoSaveLinkSettings] = .bool(newValue) }
    }

    /// One IP per line, as the web stores it.
    public var excludedIPs: String {
        get { values[Key.excludedIPs]?.stringValue ?? "" }
        set { values[Key.excludedIPs] = .string(newValue) }
    }

    /// `datetime`, `last_datetime`, `clicks` or `url`; `datetime` when unset.
    public func orderBy(_ key: String) -> String {
        values[key]?.stringValue ?? "datetime"
    }

    public mutating func setOrderBy(_ value: String, for key: String) {
        values[key] = .string(value)
    }
}
