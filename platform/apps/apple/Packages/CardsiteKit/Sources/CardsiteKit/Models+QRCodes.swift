import Foundation

// QR codes, beyond the list row (`QRCode` in Models.swift).
//
// Shapes from apps/api/internal/handlers/qr_codes_input.go (`qrCodeInput`,
// the one struct create, update and preview all decode into) and the live
// fixtures 23a–23e. The web counterpart is `QrCodePayload` in
// apps/web/src/services/qrcodes.ts plus `buildQrPayload` in lib/qrPayload.ts.

// MARK: - Types

/// One entry of `GET /qr-codes/types`: `{value, label, group}`. The server
/// lists 28, grouped as web · basic · contact · messaging · network ·
/// location · calendar · payment · app.
public struct QRCodeTypeInfo: Decodable, Sendable, Hashable, Identifiable {
    public let value: String
    public let label: String
    public let group: String

    public var id: String { value }

    enum CodingKeys: String, CodingKey {
        case value, label, group
    }

    public init(value: String, label: String, group: String) {
        self.value = value
        self.label = label
        self.group = group
    }
}

// MARK: - Full record

/// A QR code as `GET /qr-codes/{id}`, `POST /qr-codes` and
/// `PUT /qr-codes/{id}` return it, with every field the builder needs to
/// reopen a design.
///
/// `settings` holds the type's own keys (`ssid`, `first_name`, `url`, …)
/// as the client sent them, plus `_style`, where the server keeps the
/// rendering options it does not have columns for (size, error level,
/// transparency, and the gradient / eye / frame keys the generator stores
/// but cannot draw).
public struct QRCodeDesign: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let type: String
    /// `data:image/png;base64,…`, the stored rendering.
    public let imageDataURL: String?
    public let embeddedData: String?
    public let settings: [String: JSONValue]?
    /// `#rrggbb`; omitted by the server when never set.
    public let foreground: String?
    public let background: String?
    public let linkID: Int?
    public let projectID: Int?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, settings
        case imageDataURL = "qr_code"
        case embeddedData = "embedded_data"
        case foreground = "qr_code_foreground"
        case background = "qr_code_background"
        case linkID = "link_id"
        case projectID = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, name: String, type: String, imageDataURL: String?, embeddedData: String?,
                settings: [String: JSONValue]?, foreground: String? = nil, background: String? = nil,
                linkID: Int? = nil, projectID: Int? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.imageDataURL = imageDataURL
        self.embeddedData = embeddedData
        self.settings = settings
        self.foreground = foreground
        self.background = background
        self.linkID = linkID
        self.projectID = projectID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The server's `settings._style` object, empty when absent.
    public var style: [String: JSONValue] {
        settings?["_style"]?.objectValue ?? [:]
    }

    /// The type's own keys, without `_style`.
    public var contentSettings: [String: JSONValue] {
        (settings ?? [:]).filter { $0.key != "_style" }
    }

    public var pngData: Data? { QRCodePNG.decode(imageDataURL) }

    /// The same code as a list row, for inserting into or replacing in a
    /// list of ``QRCode``.
    public var summary: QRCode {
        QRCode(id: id, name: name, type: type, imageDataURL: imageDataURL, embeddedData: embeddedData,
               settings: QRCode.Settings(url: settings?["url"]?.stringValue), createdAt: createdAt)
    }
}

// MARK: - Preview

/// `POST /qr-codes/generate` → `{png, embedded_data}`. Nothing is stored.
public struct QRCodePreview: Decodable, Sendable, Hashable {
    /// `data:image/png;base64,…`.
    public let png: String
    /// The text the code encodes (`WIFI:T:WPA;S:…`, `mailto:…`, a URL…).
    public let embeddedData: String?

    enum CodingKeys: String, CodingKey {
        case png
        case embeddedData = "embedded_data"
    }

    public init(png: String, embeddedData: String?) {
        self.png = png
        self.embeddedData = embeddedData
    }

    public var pngData: Data? { QRCodePNG.decode(png) }
}

/// Decodes the `data:image/png;base64,…` URLs the QR endpoints return.
public enum QRCodePNG {
    /// The PNG bytes, or nil when the value is missing or not a base64 PNG data URL.
    public static func decode(_ dataURL: String?) -> Data? {
        guard let dataURL, let comma = dataURL.firstIndex(of: ",") else { return nil }
        let header = dataURL[..<comma]
        guard header.hasPrefix("data:image/png"), header.hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }
}

// MARK: - Payload

/// The one body for preview, create and update, as the web's
/// `buildQrPayload` builds it. Preview and save must send the same object,
/// so the image the user saw is the image that is stored.
///
/// Encoded keys: `name, type, settings, size, error_level, foreground,
/// background, background_color_transparency`, plus `link_id` and
/// `embedded_data` only when set, plus ``preservedStyle`` flattened.
///
/// Update semantics (`QrCodeHandler.Update`): the server seeds its input
/// from the stored row and decodes the body over it, so a key left out
/// keeps its stored value. Two consequences:
/// - `settings` is merged key by key, so send cleared fields as `""`
///   rather than leaving them out.
/// - The stored `embedded_data` wins over `settings` unless the body
///   overrides it. Send `embeddedData: ""` when the type or settings
///   changed, so the server encodes the new content.
public struct QRCodePayload: Encodable, Sendable, Hashable {
    public var name: String
    public var type: String
    /// String values for every type field, as the web sends them.
    public var settings: [String: JSONValue]
    public var linkID: Int?
    public var embeddedData: String?
    /// Pixels, 100–2000. The server clamps anything outside.
    public var size: Int
    /// `L`, `M`, `Q` or `H`.
    public var errorLevel: String
    /// `#rrggbb`.
    public var foreground: String
    public var background: String
    /// 0–100.
    public var backgroundColorTransparency: Int
    /// Stored style keys the generator cannot draw yet (gradient, eyes,
    /// frame), sent back unchanged on edit so a design survives the day
    /// the generator learns to draw them. Never set from a control.
    public var preservedStyle: [String: JSONValue]

    /// The `_style` keys the server stores but does not render
    /// (`qrCodeInput` in qr_codes_input.go).
    public static let unrenderedStyleKeys: Set<String> = [
        "foreground_gradient_color", "foreground_gradient_type",
        "eyes_inner_color", "eyes_outer_color",
        "inner_eye_style", "outer_eye_style",
        "frame", "frame_color", "frame_text", "frame_text_font", "frame_text_size",
    ]

    public init(name: String, type: String, settings: [String: JSONValue], linkID: Int? = nil,
                embeddedData: String? = nil, size: Int, errorLevel: String, foreground: String,
                background: String, backgroundColorTransparency: Int,
                preservedStyle: [String: JSONValue] = [:]) {
        self.name = name
        self.type = type
        self.settings = settings
        self.linkID = linkID
        self.embeddedData = embeddedData
        self.size = size
        self.errorLevel = errorLevel
        self.foreground = foreground
        self.background = background
        self.backgroundColorTransparency = backgroundColorTransparency
        self.preservedStyle = preservedStyle
    }

    /// The body as one JSON object.
    public var jsonObject: [String: JSONValue] {
        var body: [String: JSONValue] = [:]
        for (key, value) in preservedStyle where Self.unrenderedStyleKeys.contains(key) {
            body[key] = value
        }
        body["name"] = .string(name)
        body["type"] = .string(type)
        body["settings"] = .object(settings)
        body["size"] = .int(size)
        body["error_level"] = .string(errorLevel)
        body["foreground"] = .string(foreground)
        body["background"] = .string(background)
        body["background_color_transparency"] = .int(backgroundColorTransparency)
        if let linkID { body["link_id"] = .int(linkID) }
        if let embeddedData { body["embedded_data"] = .string(embeddedData) }
        return body
    }

    public func encode(to encoder: Encoder) throws {
        try JSONValue.object(jsonObject).encode(to: encoder)
    }
}
