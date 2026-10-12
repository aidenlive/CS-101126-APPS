import Foundation

// Projects, custom domains and tracking pixels: the Organise section
// (`/projects`, `/domains`, `/pixels` on the web). Shapes from fixtures
// 21a–21h and the Go handlers projects.go, domains.go and pixels.go
// (models/project.go, domain.go, pixel.go, pixel_types.go).
//
// The pickers in resource editors keep their small `ProjectOption` and
// `DomainOption` shapes (Models+Reference.swift); these are the full records
// the Organise screens edit, and each converts to its option.

// MARK: - Projects

/// A colour-coded folder for links (`GET /projects`).
public struct Project: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    public let name: String
    /// `#rrggbb` as the user chose it; `""` when never set.
    public let color: String
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case workspaceID = "workspace_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, workspaceID: Int? = nil, name: String, color: String = "",
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// The picker shape.
    public var option: ProjectOption {
        ProjectOption(id: id, name: name, color: color.isEmpty ? nil : color)
    }
}

/// The body of `POST /projects` and `PUT /projects/{id}`: both fields,
/// always. The server requires a name on create; on update it overwrites
/// what is sent.
public struct ProjectInput: Sendable, Hashable {
    public var name: String
    /// `#rrggbb`.
    public var color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }

    public init(_ project: Project) {
        self.init(name: project.name, color: project.color)
    }

    public var body: [String: JSONValue] {
        [
            "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "color": .string(color),
        ]
    }
}

// MARK: - Custom domains

/// What a domain is for (`type`): the account's own branded host, or one the
/// operator offers every account.
public enum DomainKind: Int, CaseIterable, Sendable, Hashable, Identifiable {
    case custom = 0
    case system = 1

    public var id: Int { rawValue }
}

/// How a custom domain sends visitors on (`redirect_type`). The raw values
/// are the wire's words.
public enum DomainRedirectType: String, CaseIterable, Sendable, Hashable, Identifiable {
    case permanent = "301"
    case temporary = "302"
    case cloak
    case frame

    public var id: String { rawValue }
}

/// A custom domain (`GET /domains`), with everything its editor reads.
///
/// `custom_index_url` and `custom_not_found_url` carry `omitempty` on the
/// server, so an unset URL is absent; it decodes as `""`. The scheme is
/// stored as sent: the web sends `https`, older rows hold `https://`.
public struct CustomDomain: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    /// The link served at the domain's root, when one is set.
    public let linkID: Int?
    public let scheme: String
    public let host: String
    public let customIndexURL: String
    public let customNotFoundURL: String
    /// ``DomainKind`` raw value; kept as sent so an unknown kind survives.
    public let type: Int
    public let isEnabled: Bool
    public let sslIsEnabled: Bool
    public let forceSSL: Bool
    /// ``DomainRedirectType`` raw value; `"301"` when unset.
    public let redirectType: String
    public let forwardParameters: Bool
    public let isVerified: Bool
    /// When the last DNS check ran, whatever it found.
    public let lastVerifiedAt: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, scheme, host, type
        case workspaceID = "workspace_id"
        case linkID = "link_id"
        case customIndexURL = "custom_index_url"
        case customNotFoundURL = "custom_not_found_url"
        case isEnabled = "is_enabled"
        case sslIsEnabled = "ssl_is_enabled"
        case forceSSL = "force_ssl"
        case redirectType = "redirect_type"
        case forwardParameters = "forward_parameters"
        case isVerified = "is_verified"
        case lastVerifiedAt = "last_verified_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, workspaceID: Int? = nil, linkID: Int? = nil, scheme: String = "https", host: String,
                customIndexURL: String = "", customNotFoundURL: String = "", type: Int = DomainKind.custom.rawValue,
                isEnabled: Bool = true, sslIsEnabled: Bool = false, forceSSL: Bool = false,
                redirectType: String = DomainRedirectType.permanent.rawValue, forwardParameters: Bool = false,
                isVerified: Bool = false, lastVerifiedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.linkID = linkID
        self.scheme = scheme
        self.host = host
        self.customIndexURL = customIndexURL
        self.customNotFoundURL = customNotFoundURL
        self.type = type
        self.isEnabled = isEnabled
        self.sslIsEnabled = sslIsEnabled
        self.forceSSL = forceSSL
        self.redirectType = redirectType
        self.forwardParameters = forwardParameters
        self.isVerified = isVerified
        self.lastVerifiedAt = lastVerifiedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        linkID = try c.decodeIfPresent(Int.self, forKey: .linkID)
        scheme = try c.decodeIfPresent(String.self, forKey: .scheme) ?? "https"
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        customIndexURL = try c.decodeIfPresent(String.self, forKey: .customIndexURL) ?? ""
        customNotFoundURL = try c.decodeIfPresent(String.self, forKey: .customNotFoundURL) ?? ""
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? DomainKind.custom.rawValue
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sslIsEnabled = try c.decodeIfPresent(Bool.self, forKey: .sslIsEnabled) ?? false
        forceSSL = try c.decodeIfPresent(Bool.self, forKey: .forceSSL) ?? false
        let redirect = try c.decodeIfPresent(String.self, forKey: .redirectType) ?? ""
        redirectType = redirect.isEmpty ? DomainRedirectType.permanent.rawValue : redirect
        forwardParameters = try c.decodeIfPresent(Bool.self, forKey: .forwardParameters) ?? false
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        lastVerifiedAt = try c.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// `https` or `http`, whichever way the row stores it.
    public var bareScheme: String {
        CustomDomain.bareScheme(scheme)
    }

    /// `https://go.example.com`, for display.
    public var address: String { "\(bareScheme)://\(host)" }

    public var kind: DomainKind? { DomainKind(rawValue: type) }
    public var redirect: DomainRedirectType? { DomainRedirectType(rawValue: redirectType) }

    /// The picker shape.
    public var option: DomainOption {
        DomainOption(id: id, scheme: bareScheme + "://", host: host, isEnabled: isEnabled, isVerified: isVerified)
    }

    /// `https://` → `https`, `HTTP` → `http`; anything else is `https`.
    static func bareScheme(_ raw: String) -> String {
        let trimmed = raw.lowercased()
            .replacingOccurrences(of: "://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "http" ? "http" : "https"
    }
}

/// The domain editor's state, and the bodies built from it.
///
/// A create sends every field, as the web does. An update sends only what
/// differs from the stored domain (the server treats every field as
/// optional), so opening and saving a row stored with `https://` doesn't
/// rewrite its scheme as `https`.
public struct CustomDomainInput: Sendable, Hashable {
    /// `https` or `http`.
    public var scheme: String
    public var host: String
    public var kind: DomainKind
    public var redirectType: DomainRedirectType
    public var customIndexURL: String
    public var customNotFoundURL: String
    public var sslIsEnabled: Bool
    /// Only meaningful with SSL on; sent as `false` without it.
    public var forceSSL: Bool
    public var forwardParameters: Bool

    public init(scheme: String = "https", host: String = "", kind: DomainKind = .custom,
                redirectType: DomainRedirectType = .permanent, customIndexURL: String = "",
                customNotFoundURL: String = "", sslIsEnabled: Bool = false, forceSSL: Bool = false,
                forwardParameters: Bool = false) {
        self.scheme = CustomDomain.bareScheme(scheme)
        self.host = host
        self.kind = kind
        self.redirectType = redirectType
        self.customIndexURL = customIndexURL
        self.customNotFoundURL = customNotFoundURL
        self.sslIsEnabled = sslIsEnabled
        self.forceSSL = forceSSL
        self.forwardParameters = forwardParameters
    }

    /// The editor state for a stored domain.
    public init(_ domain: CustomDomain) {
        self.init(
            scheme: domain.scheme,
            host: domain.host,
            kind: domain.kind ?? .custom,
            redirectType: domain.redirect ?? .permanent,
            customIndexURL: domain.customIndexURL,
            customNotFoundURL: domain.customNotFoundURL,
            sslIsEnabled: domain.sslIsEnabled,
            forceSSL: domain.sslIsEnabled && domain.forceSSL,
            forwardParameters: domain.forwardParameters
        )
    }

    /// The host as it is sent: trimmed, lowercased, without a scheme or path
    /// someone pasted along with it.
    public var normalizedHost: String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value
    }

    /// True when the host is something a DNS name could be: at least two
    /// labels of letters, digits and hyphens.
    public var hasValidHost: Bool {
        let value = normalizedHost
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, value.count <= 253 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    private var fields: [String: JSONValue] {
        [
            "host": .string(normalizedHost),
            "scheme": .string(scheme),
            "type": .int(kind.rawValue),
            "redirect_type": .string(redirectType.rawValue),
            "custom_index_url": .string(customIndexURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            "custom_not_found_url": .string(customNotFoundURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            "ssl_is_enabled": .bool(sslIsEnabled),
            "force_ssl": .bool(sslIsEnabled && forceSSL),
            "forward_parameters": .bool(forwardParameters),
        ]
    }

    /// `POST /domains`.
    public var createBody: [String: JSONValue] { fields }

    /// `PUT /domains/{id}`: the fields that differ from `original`. Empty
    /// when nothing changed.
    public func updateBody(from original: CustomDomain) -> [String: JSONValue] {
        let stored = CustomDomainInput(original).fields
        return fields.filter { key, value in stored[key] != value }
    }
}

/// What `POST /domains/{id}/verify` found.
public enum DomainVerification: Sendable, Hashable {
    /// The host resolves to this deployment.
    case verified(CustomDomain)
    /// It doesn't yet (422). `title` names the host; `message` says what to
    /// point it at, in the server's words. The domain is recorded as
    /// unverified.
    case notVerified(CustomDomain?, title: String, message: String?)
    /// The deployment can't check DNS right now (503): not configured, or
    /// its own lookup failed. Nothing about the domain was learned.
    case unavailable(String)
}

// MARK: - Pixels

/// A retargeting pixel (`GET /pixels`) links and bio pages can attach.
public struct TrackingPixel: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let workspaceID: Int?
    /// The provider key, matching ``PixelType/key``.
    public let type: String
    public let name: String
    /// The provider's id or code for this pixel (`pixel` on the wire).
    public let pixel: String
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, name, pixel
        case workspaceID = "workspace_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, workspaceID: Int? = nil, type: String, name: String, pixel: String = "",
                createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.type = type
        self.name = name
        self.pixel = pixel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        pixel = try c.decodeIfPresent(String.self, forKey: .pixel) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// One provider from `GET /pixels/types` (24 today).
public struct PixelType: Decodable, Sendable, Hashable, Identifiable {
    public let key: String
    public let name: String
    /// One line on what the provider tracks.
    public let description: String
    /// What the provider calls the id ("Pixel ID", "Container ID", …).
    public let fieldLabel: String
    /// Whether the provider has a no-script beacon, and so can count a visit
    /// on a public page at all (ADR-0096). Most don't yet.
    public let emitsBeacon: Bool

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, description
        case fieldLabel = "field_label"
        case emitsBeacon = "emits_beacon"
    }

    public init(key: String, name: String, description: String = "", fieldLabel: String = "", emitsBeacon: Bool = false) {
        self.key = key
        self.name = name
        self.description = description
        self.fieldLabel = fieldLabel
        self.emitsBeacon = emitsBeacon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? key
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        fieldLabel = try c.decodeIfPresent(String.self, forKey: .fieldLabel) ?? ""
        emitsBeacon = try c.decodeIfPresent(Bool.self, forKey: .emitsBeacon) ?? false
    }

    /// `google_tag_manager` → "Google Tag Manager": the web's fallback name
    /// for a provider the type list doesn't know.
    public static func fallbackName(for key: String) -> String {
        key.split(separator: "_").map { word in word.prefix(1).uppercased() + word.dropFirst() }.joined(separator: " ")
    }
}

/// The body of `POST /pixels` and `PUT /pixels/{id}`. The server requires
/// a name and a type on create.
public struct PixelInput: Sendable, Hashable {
    public var name: String
    /// A ``PixelType/key``.
    public var type: String
    public var pixel: String

    public init(name: String, type: String, pixel: String) {
        self.name = name
        self.type = type
        self.pixel = pixel
    }

    public init(_ pixel: TrackingPixel) {
        self.init(name: pixel.name, type: pixel.type, pixel: pixel.pixel)
    }

    public var body: [String: JSONValue] {
        [
            "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "type": .string(type),
            "pixel": .string(pixel.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
    }
}
