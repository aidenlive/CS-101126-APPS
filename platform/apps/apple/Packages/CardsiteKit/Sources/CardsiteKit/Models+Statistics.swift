import Foundation

// `GET /statistics/{link_id|all}` (handlers/link_statistics.go; fixtures
// 07b, 07c, 20b, 20c). Overview rows are `{date, pageviews, visitors}`
// (``DailyTraffic``); every other type is `{label, pageviews}`. An empty
// result is `data: null`.

/// Whose traffic: one resource, or everything in the workspace.
public enum StatisticsTarget: Sendable, Hashable {
    case link(Int)
    case all

    public init(linkID: Int?) {
        self = linkID.map(StatisticsTarget.link) ?? .all
    }

    var pathComponent: String {
        switch self {
        case .link(let id): return String(id)
        case .all: return "all"
        }
    }
}

/// The 11 breakdowns the server groups by.
public enum StatisticsDimension: String, CaseIterable, Sendable, Hashable, Identifiable {
    case country = "country_code"
    case continent = "continent_code"
    case city = "city_name"
    case referrer = "referrer"
    case browser = "browser_name"
    case operatingSystem = "os_name"
    case deviceType = "device_type"
    case utmSource = "utm_source"
    case utmMedium = "utm_medium"
    case utmCampaign = "utm_campaign"
    /// Hour of day, `"0"`…`"23"`, in server time (UTC), in hour order.
    case hour = "hour"

    public var id: String { rawValue }
}

/// One grouped row: a label and how many pageviews it had.
public struct StatisticsRow: Decodable, Sendable, Hashable, Identifiable {
    public let label: String
    public let pageviews: Int
    public var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, pageviews
    }

    public init(label: String, pageviews: Int) {
        self.label = label
        self.pageviews = pageviews
    }
}
