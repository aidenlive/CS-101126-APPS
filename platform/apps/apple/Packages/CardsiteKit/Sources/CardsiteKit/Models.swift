import Foundation

// Every model mirrors a body captured from the live API by
// ContractTests/native-contract.sh. Fields the app does not use are not
// decoded, and every field the server may omit or send as null is optional,
// so additive server changes never break decoding.

// MARK: - Envelopes

/// `{ "data": …, "meta": … }`. Empty lists arrive as `"data": null`.
struct DataEnvelope<Payload: Decodable>: Decodable {
    let data: Payload?
    let meta: PageMeta?
}

public struct PageMeta: Decodable, Sendable, Equatable {
    public let page: Int
    public let perPage: Int
    public let total: Int

    enum CodingKeys: String, CodingKey {
        case page, total
        case perPage = "per_page"
    }

    public init(page: Int, perPage: Int, total: Int) {
        self.page = page
        self.perPage = perPage
        self.total = total
    }
}

/// One page of a paginated list.
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let meta: PageMeta

    public var hasMore: Bool { meta.page * meta.perPage < meta.total }

    public init(items: [Item], meta: PageMeta) {
        self.items = items
        self.meta = meta
    }
}

extension Page: Equatable where Item: Equatable {}

/// `{ "error": { "title", "code", "message"?, … } }`.
struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let title: String?
        let code: Int?
        let message: String?
        // plan_limit_exceeded
        let limit: String?
        let current: Int?
        let max: Int?
        // plan_capability_required
        let capability: String?
        let label: String?
        // 409 from a stale block PUT: who saved last.
        let lastEditor: LastEditor?

        struct LastEditor: Decodable {
            let name: String?
            let userID: Int?

            enum CodingKeys: String, CodingKey {
                case name
                case userID = "user_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case title, code, message, limit, current, max, capability, label
            case lastEditor = "last_editor"
        }
    }

    let error: Body
}

// MARK: - Account

public struct User: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public var email: String
    public var name: String
    public var twoFactorEnabled: Bool?
    public var planID: Int?
    public var planExpirationDate: Date?
    public var language: String?
    public var timezone: String?
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case email, name, language, timezone
        case twoFactorEnabled = "twofa_enabled"
        case planID = "plan_id"
        case planExpirationDate = "plan_expiration_date"
        case createdAt = "created_at"
    }

    public init(id: Int, email: String, name: String, twoFactorEnabled: Bool? = nil, planID: Int? = nil,
                planExpirationDate: Date? = nil, language: String? = nil, timezone: String? = nil,
                createdAt: Date? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.twoFactorEnabled = twoFactorEnabled
        self.planID = planID
        self.planExpirationDate = planExpirationDate
        self.language = language
        self.timezone = timezone
        self.createdAt = createdAt
    }

    /// The first letter of the name, or of the email when the name is blank.
    public var initial: String {
        let source = name.trimmingCharacters(in: .whitespaces).isEmpty ? email : name
        return source.first.map { String($0).uppercased() } ?? "?"
    }
}

/// `POST /auth/login` and `/auth/register` payload.
struct AuthPayload: Decodable {
    let token: String?
    let user: User?
    let twofaRequired: Bool?
    let recoveryCodesRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case token, user
        case twofaRequired = "twofa_required"
        case recoveryCodesRemaining = "recovery_codes_remaining"
    }
}

public struct Session: Sendable, Equatable {
    public let token: String
    public let user: User
    /// Present when the sign-in used a recovery code.
    public let recoveryCodesRemaining: Int?
}

public enum SignInOutcome: Sendable, Equatable {
    case signedIn(Session)
    /// The account has two-factor authentication: sign in again with a code.
    case twoFactorRequired
}

public struct Workspace: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let isPersonal: Bool
    public let role: String?
    public let storageBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id"
        case name, role
        case isPersonal = "is_personal"
        case storageBytes = "storage_bytes"
    }
}

public struct Plan: Decodable, Sendable, Equatable, Identifiable {
    public struct Settings: Decodable, Sendable, Equatable {
        public let customSlugsLimit: Int?
        public let domainsLimit: Int?
        public let teamsLimit: Int?
        public let storageBytesLimit: Int64?

        enum CodingKeys: String, CodingKey {
            case customSlugsLimit = "custom_slugs_limit"
            case domainsLimit = "domains_limit"
            case teamsLimit = "teams_limit"
            case storageBytesLimit = "storage_bytes_limit"
        }
    }

    public let id: Int
    public let name: String
    public let description: String?
    /// Left out by the server when the plan has no list price (Enterprise).
    public let monthlyPrice: Double?
    public let settings: Settings?

    enum CodingKeys: String, CodingKey {
        case id, name, description, settings
        case monthlyPrice = "monthly_price"
    }
}

/// `GET /account/plan`. Carries no usage figures (the API has none yet).
public struct AccountPlan: Decodable, Sendable, Equatable {
    public let planID: Int?
    public let planExpirationDate: Date?
    public let paymentProcessor: String?

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case planExpirationDate = "plan_expiration_date"
        case paymentProcessor = "payment_processor"
    }

    public var hasPaidSubscription: Bool { !(paymentProcessor ?? "").isEmpty }
}

// MARK: - Resources

/// A resource with an address: short link, bio page, file, etc.
/// The API calls the slug `url` and the destination `location_url`.
public struct Resource: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public let id: Int
    public let workspaceID: Int?
    public let type: String
    public let slug: String
    public let destination: String?
    public let clicks: Int
    public let isEnabled: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    public let lifecycleState: String?

    enum CodingKeys: String, CodingKey {
        case id, type, clicks
        case workspaceID = "workspace_id"
        case slug = "url"
        case destination = "location_url"
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lifecycleState = "lifecycle_state"
    }

    public init(id: Int, workspaceID: Int? = nil, type: String = LinkKind.shortLink, slug: String,
                destination: String?, clicks: Int = 0, isEnabled: Bool = true, createdAt: Date? = nil,
                updatedAt: Date? = nil, lifecycleState: String? = "active") {
        self.id = id
        self.workspaceID = workspaceID
        self.type = type
        self.slug = slug
        self.destination = destination
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
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? LinkKind.shortLink
        slug = try c.decode(String.self, forKey: .slug)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        clicks = try c.decodeIfPresent(Int.self, forKey: .clicks) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        lifecycleState = try c.decodeIfPresent(String.self, forKey: .lifecycleState)
    }

    public var isBioPage: Bool { type == LinkKind.bioPage }
    /// Anything other than "active" means the address is in its release window.
    /// A missing or empty state is unknown, not lapsing: `/resources/recent`
    /// sends `""` because it does not select the lifecycle columns.
    public var isLapsing: Bool {
        guard let lifecycleState, !lifecycleState.isEmpty else { return false }
        return lifecycleState != "active"
    }
}

public enum LinkKind {
    public static let shortLink = "link"
    public static let bioPage = "biolink"
}

public struct QRCode: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public struct Settings: Decodable, Sendable, Equatable, Hashable {
        public let url: String?
    }

    public let id: Int
    public let name: String
    public let type: String
    /// `data:image/png;base64,…` — the server's rendering, 256 × 256.
    public let imageDataURL: String?
    public let embeddedData: String?
    public let settings: Settings?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, settings
        case imageDataURL = "qr_code"
        case embeddedData = "embedded_data"
        case createdAt = "created_at"
    }

    public init(id: Int, name: String, type: String = "url", imageDataURL: String?, embeddedData: String?,
                settings: Settings? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.imageDataURL = imageDataURL
        self.embeddedData = embeddedData
        self.settings = settings
        self.createdAt = createdAt
    }

    /// Decoded PNG bytes, or nil if the field is missing or not a base64 PNG data URL.
    public var pngData: Data? {
        guard let imageDataURL, let comma = imageDataURL.firstIndex(of: ",") else { return nil }
        let header = imageDataURL[..<comma]
        guard header.hasPrefix("data:image/png"), header.hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(imageDataURL[imageDataURL.index(after: comma)...]))
    }

    /// What a scan opens: the encoded URL or text.
    public var target: String? { settings?.url ?? embeddedData }
}

// MARK: - Statistics

public struct DailyTraffic: Decodable, Sendable, Equatable, Identifiable {
    /// `YYYY-MM-DD`.
    public let date: String
    public let pageviews: Int
    public let visitors: Int

    public var id: String { date }
    /// Local midnight of the day, for charts that bin by local day.
    public var day: Date? { CardsiteJSON.parseDay(date, in: .current) }

    public init(date: String, pageviews: Int, visitors: Int) {
        self.date = date
        self.pageviews = pageviews
        self.visitors = visitors
    }
}

public struct TrafficBreakdown: Decodable, Sendable, Equatable, Identifiable {
    public let label: String
    public let pageviews: Int
    public var id: String { label }
}

public enum BreakdownDimension: String, Sendable, CaseIterable {
    case referrer = "referrer"
    case country = "country_code"
    case device = "device_type"
    case os = "os_name"
    case browser = "browser_name"
}

/// `GET /statistics` — account-wide counts.
public struct AccountSummary: Decodable, Sendable, Equatable {
    public let links: Int
    public let biolinks: Int
    public let qrCodes: Int
    public let totalClicks: Int

    enum CodingKeys: String, CodingKey {
        case links, biolinks
        case qrCodes = "qr_codes"
        case totalClicks = "total_clicks"
    }
}
