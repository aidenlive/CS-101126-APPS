import Foundation

/// Address rules from docs/brand/Cardsite-Overview.md → Domains and Card view.
public struct AddressBook: Sendable, Equatable {
    /// Host for standard addresses, `card.site`.
    public let publicHost: String

    public init(publicHost: String = "card.site") {
        self.publicHost = publicHost
    }

    /// `https://card.site/slug`
    public func url(for slug: String) -> URL? {
        URL(string: "https://\(publicHost)/\(slug)")
    }

    /// `card.site/slug`, for display.
    public func display(for slug: String) -> String {
        "\(publicHost)/\(slug)"
    }

    /// `https://card.site/@slug` — the resource's summary card.
    public func cardURL(for slug: String) -> URL? {
        URL(string: "https://\(publicHost)/@\(slug)")
    }
}

/// Slug rules the client enforces.
///
/// The API does not validate slug characters (it only checks that the slug
/// is non-empty and not taken), so the app keeps addresses to characters
/// that survive any URL context: letters, digits, `-` and `_`, starting with
/// a letter or digit, at most 64 characters. The Overview's own example,
/// `Demo-Q4-Review`, fits.
public enum Slug {
    public static let maxLength = 64

    public enum Problem: Sendable, Equatable {
        case empty
        case tooLong
        case invalidCharacters
        case mustStartAlphanumeric
    }

    public static func problem(with slug: String) -> Problem? {
        if slug.isEmpty { return .empty }
        if slug.count > maxLength { return .tooLong }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        if slug.contains(where: { !allowed.contains($0) }) { return .invalidCharacters }
        guard let first = slug.first, first.isASCII, first.isLetter || first.isNumber else {
            return .mustStartAlphanumeric
        }
        return nil
    }

    public static func message(for problem: Problem) -> String {
        switch problem {
        case .empty: return String(localized: "Choose an address.")
        case .tooLong: return String(localized: "Keep the address to \(maxLength) characters or fewer.")
        case .invalidCharacters: return String(localized: "Use letters, numbers, hyphens and underscores only.")
        case .mustStartAlphanumeric: return String(localized: "Start the address with a letter or number.")
        }
    }

    /// Turns free text ("Spring Menu 2026!") into a usable slug ("Spring-Menu-2026").
    public static func suggestion(from text: String) -> String {
        var result = ""
        var lastWasSeparator = false
        for character in text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil) {
            if character.isASCII, character.isLetter || character.isNumber {
                result.append(character)
                lastWasSeparator = false
            } else if !result.isEmpty, !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return String(result.prefix(maxLength))
    }

    /// A random 7-character address from an alphabet without look-alikes.
    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<7).map { _ in alphabet.randomElement(using: &generator)! })
    }

    public static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }
}

/// Destination URL rules: absolute http(s) with a host.
public enum Destination {
    /// Accepts "example.com/menu" and returns "https://example.com/menu".
    public static func normalized(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), host.contains(".") else { return nil }
        return url
    }
}
