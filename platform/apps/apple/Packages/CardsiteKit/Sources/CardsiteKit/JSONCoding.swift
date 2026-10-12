import Foundation

/// JSON coding matched to what the Cardsite API actually sends
/// (see ContractTests/README.md):
///
/// - Timestamps are RFC 3339 in UTC with a variable number of fractional
///   digits (Go trims trailing zeros, so 0–9 digits appear).
/// - Keys are snake_case; every model maps them explicitly, so no key
///   strategy is applied here.
public enum CardsiteJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseTimestamp(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised timestamp \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Parses RFC 3339 timestamps with any number of fractional digits.
    ///
    /// The fraction is split off and added back manually because Foundation's
    /// ISO 8601 parsers only accept a fixed fraction width on some platforms.
    public static func parseTimestamp(_ raw: String) -> Date? {
        var base = Substring(raw)
        var fraction: Double = 0
        if let dot = raw.firstIndex(of: ".") {
            let afterDot = raw[raw.index(after: dot)...]
            let digits = afterDot.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty else { return nil }
            fraction = Double("0." + digits) ?? 0
            base = raw[..<dot] + afterDot.dropFirst(digits.count)
        }
        let candidate = String(base)
        let styles: [Date.ISO8601FormatStyle] = [
            Date.ISO8601FormatStyle(),
            Date.ISO8601FormatStyle(timeZoneSeparator: .colon),
        ]
        for style in styles {
            if let date = try? style.parse(candidate) {
                return date.addingTimeInterval(fraction)
            }
        }
        return nil
    }

    /// `YYYY-MM-DD` in UTC, the format the statistics endpoints take and return.
    public static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(parts.year ?? 1970, 4))-\(pad(parts.month ?? 1, 2))-\(pad(parts.day ?? 1, 2))"
    }

    /// Inverse of ``dayString(_:)``. Pass `.current` to get local midnight,
    /// which is what charts binned by local day expect.
    public static func parseDay(_ raw: String, in timeZone: TimeZone = TimeZone(identifier: "UTC") ?? .gmt) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
