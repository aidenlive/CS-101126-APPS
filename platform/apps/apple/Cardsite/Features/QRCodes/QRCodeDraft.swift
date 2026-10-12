import SwiftUI
import CardsiteKit

/// Everything the builder edits, and the one function that turns it into
/// the request body.
///
/// Preview, create and update all send ``payload``, the same object the
/// web's `buildQrPayload` (apps/web/src/lib/qrPayload.ts) produces, so the
/// image previewed is the image saved and a code edited on either platform
/// opens unchanged on the other.
struct QRCodeDraft: Equatable {
    var name = ""
    private(set) var type = QRCodeCatalog.defaultType
    /// The type's keys as strings, plus whatever else the stored code had
    /// (including `_style`, which the server rewrites on every save).
    var settings: [String: JSONValue] = [:]
    /// The short link a `url_dynamic` code encodes.
    var linkID: Int?

    // Rendered by the generator.
    var size = 500
    var errorLevel = "M"
    var foreground = "#000000"
    var background = "#ffffff"
    var transparency = 0

    /// Gradient, eye and frame keys from the stored `_style`. The generator
    /// can't draw them, so there are no controls; they are sent back
    /// unchanged so the design survives.
    private(set) var preservedStyle: [String: JSONValue] = [:]

    /// The type and content as loaded, when editing. Used to tell a restyle
    /// or rename from new content.
    private(set) var loadedContent: Content?

    struct Content: Equatable {
        let type: String
        let settings: [String: JSONValue]
    }

    static let sizeRange = 100...2000
    static let sizeStep = 50

    init() {}

    /// A new code that encodes `url`. A short link on the public host becomes
    /// a dynamic code; the picker then matches it to the link.
    init(prefill url: URL, publicHost: String) {
        let isShortLink = url.host()?.lowercased() == publicHost.lowercased()
        type = isShortLink ? QRCodeCatalog.dynamicURLType : QRCodeCatalog.defaultType
        settings = ["url": .string(url.absoluteString)]
        let host = url.host() ?? ""
        let path = url.path()
        name = path.isEmpty || path == "/" ? host : host + path
    }

    /// An existing code, with every stored control restored as the web
    /// builder restores it.
    init(design: QRCodeDesign) {
        name = design.name
        type = design.type.isEmpty ? QRCodeCatalog.defaultType : design.type
        settings = design.settings ?? [:]
        linkID = design.linkID
        if let value = design.foreground, !value.isEmpty { foreground = value.lowercased() }
        if let value = design.background, !value.isEmpty { background = value.lowercased() }

        let style = design.style
        if let value = style["size"]?.intValue, value > 0 { size = value }
        if let value = style["error_level"]?.stringValue, !value.isEmpty { errorLevel = value.uppercased() }
        if let value = style["background_color_transparency"]?.intValue { transparency = min(max(value, 0), 100) }
        preservedStyle = style.filter { QRCodePayload.unrenderedStyleKeys.contains($0.key) }
        loadedContent = Content(type: type, settings: Self.content(of: Self.materialized(settings, for: type)))
    }

    // MARK: Type and fields

    /// Switches type. The fields of the old type are cleared, as on the web.
    mutating func selectType(_ newType: String) {
        guard newType != type else { return }
        type = newType
        settings = [:]
        if newType != QRCodeCatalog.dynamicURLType { linkID = nil }
    }

    func text(for field: QRField) -> String {
        settings[field.key]?.fieldText ?? field.defaultValue ?? ""
    }

    mutating func setText(_ value: String, for field: QRField) {
        var text = value
        if field.isNumeric { text = text.replacingOccurrences(of: ",", with: ".") }
        if let limit = field.maxLength, text.count > limit { text = String(text.prefix(limit)) }
        settings[field.key] = .string(text)
    }

    func string(_ key: String) -> String {
        settings[key]?.fieldText ?? ""
    }

    mutating func setString(_ value: String, for key: String) {
        settings[key] = .string(value)
    }

    /// The encoded URL of a `url_dynamic` code.
    var dynamicURL: String { string("url") }

    /// True once there is something to encode; until then a preview would
    /// only come back 400 "no data to encode".
    var hasContent: Bool {
        if type == QRCodeCatalog.dynamicURLType {
            return !dynamicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return QRCodeCatalog.fields(for: type)
            .filter(\.countsAsContent)
            .contains { !text(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Payload

    /// The request body for preview, create and update.
    ///
    /// - Defaults a control shows (WPA, Call, USD, INR…) are written out, so
    ///   the code encodes what the form shows.
    /// - Every field of the type is sent, cleared ones as "", because the
    ///   server merges `settings` on update and would keep an old value for
    ///   a missing key.
    /// - When editing and the content changed, `embedded_data` is sent as
    ///   "": otherwise the server re-encodes the stored text and the new
    ///   content never reaches the image.
    var payload: QRCodePayload {
        let body = Self.materialized(settings, for: type)
        let contentChanged = loadedContent.map {
            $0 != Content(type: type, settings: Self.content(of: body))
        } ?? false
        return QRCodePayload(
            name: trimmedName,
            type: type,
            settings: body,
            linkID: type == QRCodeCatalog.dynamicURLType ? linkID : nil,
            embeddedData: contentChanged ? "" : nil,
            size: min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound),
            errorLevel: errorLevel,
            foreground: foreground,
            background: background,
            backgroundColorTransparency: transparency,
            preservedStyle: preservedStyle
        )
    }

    /// `settings` with every field of `type` present: the default a control
    /// shows, "false" for a toggle, "" for an empty field.
    private static func materialized(_ settings: [String: JSONValue], for type: String) -> [String: JSONValue] {
        var body = settings
        for field in QRCodeCatalog.fields(for: type) where body[field.key] == nil {
            switch field.kind {
            case .toggle: body[field.key] = .string("false")
            default: body[field.key] = .string(field.defaultValue ?? "")
            }
        }
        return body
    }

    /// Settings without `_style` and without empty strings, so a field the
    /// form adds as "" doesn't count as a content change.
    private static func content(of settings: [String: JSONValue]) -> [String: JSONValue] {
        settings.filter { key, value in
            key != "_style" && value != .string("")
        }
    }
}

// MARK: - Colour

/// `#rrggbb` ⇄ `Color`, for the colour wells. These colours are the user's
/// data, not design tokens.
enum QRHexColor {
    static func color(_ hex: String) -> Color? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let resolved = Color.Resolved(
            red: Float((value >> 16) & 255) / 255,
            green: Float((value >> 8) & 255) / 255,
            blue: Float(value & 255) / 255
        )
        return Color(resolved)
    }

    static func hex(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        func byte(_ component: Float) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }

    /// A binding to a hex string as a `Color`.
    static func binding(_ hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding(
            get: { color(hex.wrappedValue) ?? fallback },
            set: { hex.wrappedValue = Self.hex($0) }
        )
    }
}

// MARK: - Floating local time

/// The event fields hold the author's wall-clock time, `YYYY-MM-DDTHH:mm`
/// with no zone, as the web's `datetime-local` input writes it. The
/// generator renders it as floating time, so the event reads the same in
/// every time zone.
enum QRFloatingTime {
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }

    static func date(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return formatter().date(from: String(text.prefix(16)))
    }

    static func string(_ date: Date) -> String {
        formatter().string(from: date)
    }

    /// The next whole hour, a sensible first value for a new start time.
    static func nextHour(after date: Date = .now) -> Date {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? date
    }
}
