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

// MARK: - JSONValue

/// Any JSON value. Use it for request bodies with mixed types and for
/// server objects whose keys vary by type (link `settings`, block
/// `settings`, QR `settings`, plan settings).
///
/// Decoding tries, in order: null, Bool, Int, Double, String, array,
/// object. A whole number therefore decodes as `.int`; use ``doubleValue``
/// when either is acceptable.
public enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // MARK: Accessors

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// An `.int`, or a `.double` with no fractional part.
    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(exactly: value)
        default: return nil
        }
    }

    /// A `.double` or an `.int`.
    public var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool { self == .null }

    /// The member named `key` of an object; nil for a missing key or a
    /// value that is not an object.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// The element at `index` of an array; nil when out of range or not an array.
    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
