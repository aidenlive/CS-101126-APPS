import SwiftUI

/// `#rrggbb` ⇄ `Color`, for the colour wells: a QR code's foreground and
/// background, a bio page block's colours. These colours are the user's
/// data, stored by the server as hex, not design tokens.
enum HexColor {
    /// Accepts `#rgb`, `#rrggbb` and `#rrggbbaa`, with or without `#`.
    static func color(from raw: String) -> Color? {
        var digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        func channel(_ shift: UInt64) -> Float { Float((value >> shift) & 0xFF) / 255 }
        let resolved = Color.Resolved(
            colorSpace: .sRGB,
            red: channel(hasAlpha ? 24 : 16),
            green: channel(hasAlpha ? 16 : 8),
            blue: channel(hasAlpha ? 8 : 0),
            opacity: hasAlpha ? channel(0) : 1
        )
        return Color(resolved)
    }

    /// `#rrggbb` in sRGB, lowercase. Alpha is dropped: neither the QR
    /// generator nor the page renderer reads it.
    static func hex(from color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        func byte(_ component: Float) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }

    /// A binding to a hex string as a `Color`, for a `ColorPicker`.
    static func binding(_ hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding(
            get: { color(from: hex.wrappedValue) ?? fallback },
            set: { hex.wrappedValue = Self.hex(from: $0) }
        )
    }
}
