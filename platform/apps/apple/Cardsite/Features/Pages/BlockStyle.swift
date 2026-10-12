import SwiftUI
import StudioKit
import CardsiteKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// How blocks look in the editor: glyph, tint, one-line summary, library
// grouping, and the hex ↔ Color bridge the colour fields need.

// MARK: - Glyph

enum BlockGlyph {
    /// An SF Symbol per block type. The registry sends Font Awesome class
    /// names, which have no meaning here; unknown types get a neutral glyph.
    static func systemImage(for type: String) -> String {
        symbols[type] ?? "square.dashed"
    }

    private static let symbols: [String: String] = [
        "link": "link",
        "heading": "textformat.size",
        "paragraph": "text.alignleft",
        "avatar": "person.crop.circle",
        "image": "photo",
        "socials": "person.2.wave.2",
        "email_collector": "envelope",
        "phone_collector": "phone",
        "contact_collector": "person.crop.rectangle",
        "vcard": "person.text.rectangle",
        "map": "mappin.and.ellipse",
        "soundcloud": "waveform",
        "spotify": "music.note",
        "youtube": "play.rectangle",
        "twitch": "gamecontroller",
        "vimeo": "play.rectangle.on.rectangle",
        "tiktok_video": "music.note.tv",
        "paypal": "creditcard",
        "business_hours": "clock",
        "modal_text": "macwindow",
        "header": "rectangle.topthird.inset.filled",
        "rss_feed": "dot.radiowaves.up.forward",
        "custom_html": "chevron.left.forwardslash.chevron.right",
        "code": "terminal",
        "alert": "bell",
        "divider": "minus",
        "image_grid": "square.grid.2x2",
        "list": "list.bullet",
        "twitter_profile": "bubble.left",
        "tiktok_profile": "music.note.tv",
        "pinterest_profile": "pin",
        "snapchat": "camera",
        "twitter_tweet": "bubble.left",
        "twitter_video": "bubble.left",
        "instagram_media": "camera.aperture",
        "tumblr_post": "text.bubble",
        "bluesky_post": "cloud",
        "applemusic": "music.note",
        "tidal": "music.quarternote.3",
        "mixcloud": "headphones",
        "bandcamp": "music.mic",
        "vk_video": "video",
        "google_form": "doc.text",
        "canva": "paintpalette",
        "kick": "video",
        "big_link": "arrow.up.forward.square",
        "featured_link": "star",
        "cta": "megaphone",
        "audio": "speaker.wave.2",
        "video": "film",
        "file": "arrow.down.doc",
        "iframe": "rectangle.on.rectangle",
        "faq": "questionmark.circle",
        "countdown": "hourglass",
        "external_item": "shippingbox",
        "share": "square.and.arrow.up",
        "coupon": "ticket",
        "timeline": "list.number",
        "youtube_feed": "play.square.stack",
        "markdown": "doc.richtext",
        "image_slider": "photo.on.rectangle",
        "review": "star.bubble",
        "weather": "cloud.sun",
        "counter": "number",
        "image_comparison": "square.split.2x1",
        "appointment_calendar": "calendar.badge.clock",
        "typeform": "list.bullet.rectangle",
        "calendly": "calendar",
        "discord": "bubble.left.and.bubble.right",
        "facebook": "person.2",
        "reddit": "text.bubble",
        "pdf_document": "doc.richtext",
        "powerpoint_presentation": "rectangle.on.rectangle.angled",
        "excel_spreadsheet": "tablecells",
        "rumble": "play.circle",
        "telegram": "paperplane",
        "donation": "heart",
        "product": "cube",
        "service": "person.crop.circle.badge.checkmark",
        "cashapp": "dollarsign.circle",
        "venmo": "iphone",
        "progress_bar": "chart.bar",
        "social_proof": "hand.thumbsup",
        "linkedin_profile": "person.crop.square",
        "instagram_feed": "square.grid.3x3",
    ]
}

/// The leading tile of a block row and of the library: the type's own
/// colour as a soft wash, with the glyph in Studio ink so it reads in every
/// appearance and contrast setting.
struct BlockGlyphTile: View {
    let type: String
    let color: String?
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
            .fill(Color.studioSurface3)
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                    .fill((color.flatMap(BlockHexColor.color(from:)) ?? Color.studioAccent).opacity(0.22))
            )
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: BlockGlyph.systemImage(for: type))
                    .imageScale(.medium)
                    .foregroundStyle(Color.studioText)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Summary

enum BlockSummary {
    /// One line from the block's main field: the first text-like field the
    /// type declares that has a value, else the first asset, else nil.
    static func line(for block: BioBlock, draft: BlockDraft?, type: BlockType?) -> String? {
        let settings = draft?.settings ?? block.settings
        let location = draft?.locationURL ?? block.locationURL ?? ""
        let fields = type?.fields ?? BlockFieldInference.fields(for: settings)

        func value(of field: BlockField) -> String {
            let raw = field.name == "location_url" ? location : (settings[field.name]?.displayString ?? "")
            return raw
                .split(whereSeparator: \.isNewline)
                .first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        }

        for field in fields {
            switch field.fieldKind {
            case .text, .url, .textarea, .richText:
                let text = value(of: field)
                if !text.isEmpty { return text }
            default:
                continue
            }
        }
        for field in fields {
            switch field.fieldKind {
            case .image, .file, .embed, .code:
                let text = value(of: field)
                if !text.isEmpty {
                    return URL(string: text)?.lastPathComponent.nonEmpty ?? text
                }
            default:
                continue
            }
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Library grouping

enum BlockCategory {
    /// The web palette's order.
    static let order = ["standard", "forms", "advanced", "embeds", "payments"]

    static func title(_ category: String) -> String {
        switch category {
        case "standard": return String(localized: "Standard")
        case "forms": return String(localized: "Forms")
        case "advanced": return String(localized: "Advanced")
        case "embeds": return String(localized: "Embeds")
        case "payments": return String(localized: "Payments")
        default:
            return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func rank(_ category: String) -> Int {
        order.firstIndex(of: category) ?? order.count
    }
}

// MARK: - Inference

/// Field specs for a block whose type the registry does not describe (an
/// older type, or a catalogue that failed to load): one field per stored
/// key, its kind read from the value. The web does the same.
enum BlockFieldInference {
    static func fields(for settings: [String: JSONValue]) -> [BlockField] {
        settings.keys.sorted().map { key in
            let kind: String
            switch settings[key] {
            case .bool: kind = "boolean"
            case .int, .double: kind = "number"
            case .string(let value):
                if key.hasSuffix("color"), value.hasPrefix("#") {
                    kind = "color"
                } else if key.hasSuffix("url") {
                    kind = "url"
                } else {
                    kind = "text"
                }
            default: kind = "structured"
            }
            return BlockField(name: key, kind: kind, label: humanized(key))
        }
    }

    static func humanized(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Hex colour

/// `#rrggbb` ↔ `Color`, for the colour fields the server stores as hex.
enum BlockHexColor {
    /// Accepts `#rgb`, `#rrggbb` and `#rrggbbaa`, with or without `#`.
    static func color(from raw: String) -> Color? {
        var digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// `#rrggbb` in sRGB, lowercase, alpha dropped (the renderer ignores it).
    static func hex(from color: Color) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        #if canImport(UIKit)
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #elseif canImport(AppKit)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        red = srgb.redComponent
        green = srgb.greenComponent
        blue = srgb.blueComponent
        #endif
        func byte(_ component: CGFloat) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return "#" + [red, green, blue].map { component in
            let digits = String(byte(component), radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }
}
