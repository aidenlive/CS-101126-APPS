import Foundation

// Uploads, data records and activity logs. Shapes from fixtures 26y–26z6
// and models/upload.go, datum.go, user_log.go.

// MARK: - Uploads

/// A stored image or file (`/uploads`). Keyed by `upload_id`, not `id`.
public struct UploadItem: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// The stored file name (random).
    public let name: String
    /// The name it was uploaded with, for display.
    public let originalName: String
    public let fileExtension: String
    public let mimeType: String
    public let size: Int64
    /// `file`, `image`, `avatar`, `favicon` or `logo`.
    public let type: String
    /// The public address of the file.
    public let url: String
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case name, size, type, url
        case id = "upload_id"
        case originalName = "original_name"
        case fileExtension = "extension"
        case mimeType = "mime_type"
        case createdAt = "created_at"
    }

    public init(id: Int, name: String, originalName: String, fileExtension: String, mimeType: String,
                size: Int64, type: String, url: String, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.size = size
        self.type = type
        self.url = url
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        originalName = try c.decodeIfPresent(String.self, forKey: .originalName) ?? ""
        fileExtension = try c.decodeIfPresent(String.self, forKey: .fileExtension) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? "application/octet-stream"
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? UploadType.file.rawValue
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// By MIME type, as the web gallery decides: an avatar or a logo is an image too.
    public var isImage: Bool { mimeType.hasPrefix("image/") }
    public var displayName: String { originalName.isEmpty ? name : originalName }
    public var address: URL? { URL(string: url) }
}

/// What an upload is for; decides which MIME types the server accepts.
public enum UploadType: String, Sendable, Hashable, CaseIterable, Codable {
    case file, image, avatar, favicon, logo
}

/// The list filter (`kind=`), by what the file is.
public enum UploadKind: String, Sendable, Hashable, CaseIterable, Codable {
    case image, document
}

public enum UploadRules {
    /// The server's default per-file cap (`config.DefaultMaxFileBytes`).
    public static let maxBytes: Int64 = 10 * 1024 * 1024
    /// `services.AllowedImageTypes`. SVG is refused on purpose.
    public static let imageMIMETypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]
    /// `services.AllowedFileTypes`: images plus these documents.
    public static let fileMIMETypes: Set<String> = imageMIMETypes.union([
        "application/pdf", "text/plain", "text/csv", "application/json", "application/zip",
    ])
}

// MARK: - Data records

/// A form submission collected by a bio page block (`/data`).
public struct DataRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let biolinkBlockID: Int?
    public let linkID: Int?
    /// The collecting block's type: `email_collector`, `phone_collector`,
    /// `contact_collector`.
    public let type: String
    /// What the visitor submitted, field by field.
    public let data: [String: JSONValue]
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, data
        case biolinkBlockID = "biolink_block_id"
        case linkID = "link_id"
        case createdAt = "datetime"
    }

    public init(id: Int, biolinkBlockID: Int? = nil, linkID: Int? = nil, type: String,
                data: [String: JSONValue], createdAt: Date? = nil) {
        self.id = id
        self.biolinkBlockID = biolinkBlockID
        self.linkID = linkID
        self.type = type
        self.data = data
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        biolinkBlockID = try c.decodeIfPresent(Int.self, forKey: .biolinkBlockID)
        linkID = try c.decodeIfPresent(Int.self, forKey: .linkID)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        data = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .data)) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// Fields sorted by key, values as display text.
    public var fields: [DataRecordField] {
        data.keys.sorted().map { key in DataRecordField(key: key, value: Self.text(data[key] ?? .null)) }
    }

    /// A short human rendering of a submitted value.
    static func text(_ value: JSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .bool(let bool): return bool ? "true" : "false"
        case .int(let int): return String(int)
        case .double(let double): return String(double)
        case .null: return ""
        case .array(let values): return values.map(text).joined(separator: ", ")
        case .object(let members):
            return members.keys.sorted().map { "\($0): \(text(members[$0] ?? .null))" }.joined(separator: ", ")
        }
    }
}

/// One submitted field of a ``DataRecord``, as display text.
public struct DataRecordField: Sendable, Hashable, Identifiable {
    public let key: String
    public let value: String
    public var id: String { key }

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// The type filter. Raw values are the block types the server stores.
public enum DataRecordKind: String, Sendable, Hashable, CaseIterable, Codable {
    case contact = "contact_collector"
    case mail = "email_collector"
    case phone = "phone_collector"
}

// MARK: - Activity logs

/// One account event (`/logs`): sign-ins and security changes.
public struct ActivityLogEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// `login`, `login.recovery_code`, `twofa.enabled`, `twofa.disabled`, …
    public let type: String
    public let ip: String
    public let deviceType: String?
    public let osName: String?
    public let browserName: String?
    public let countryCode: String?
    public let cityName: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, ip
        case deviceType = "device_type"
        case osName = "os_name"
        case browserName = "browser_name"
        case countryCode = "country_code"
        case cityName = "city_name"
        case createdAt = "datetime"
    }

    public init(id: Int, type: String, ip: String, deviceType: String? = nil, osName: String? = nil,
                browserName: String? = nil, countryCode: String? = nil, cityName: String? = nil,
                createdAt: Date? = nil) {
        self.id = id
        self.type = type
        self.ip = ip
        self.deviceType = deviceType
        self.osName = osName
        self.browserName = browserName
        self.countryCode = countryCode
        self.cityName = cityName
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        ip = try c.decodeIfPresent(String.self, forKey: .ip) ?? ""
        deviceType = try c.decodeIfPresent(String.self, forKey: .deviceType)
        osName = try c.decodeIfPresent(String.self, forKey: .osName)
        browserName = try c.decodeIfPresent(String.self, forKey: .browserName)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        cityName = try c.decodeIfPresent(String.self, forKey: .cityName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// The device filter on `/logs` (`device_type=`).
public enum LogDeviceType: String, Sendable, Hashable, CaseIterable, Codable {
    case desktop, mobile, tablet
}
