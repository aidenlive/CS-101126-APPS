import Foundation

// The dashboard: Home in the app, `/dashboard` on the web
// (apps/web/src/pages/dashboard/DashboardPage.tsx). Shapes from fixtures
// 20a–20d and the Go handlers (statistics.go, link_statistics.go,
// resources.go). Daily traffic reuses ``DailyTraffic``; the recent feed
// reuses ``Resource``.

/// `GET /statistics`: counts for the current workspace.
///
/// The server caches this for 5 minutes per user (not per workspace), so a
/// count can lag a create, and can briefly show the previous workspace's
/// figures after a switch.
public struct DashboardSummary: Decodable, Sendable, Hashable {
    public let links: Int
    public let biolinks: Int
    public let qrCodes: Int
    public let projects: Int
    public let domains: Int
    public let pixels: Int
    /// Every click on every resource, all time.
    public let totalClicks: Int

    enum CodingKeys: String, CodingKey {
        case links, biolinks, projects, domains, pixels
        case qrCodes = "qr_codes"
        case totalClicks = "total_clicks"
    }

    public init(links: Int = 0, biolinks: Int = 0, qrCodes: Int = 0, projects: Int = 0,
                domains: Int = 0, pixels: Int = 0, totalClicks: Int = 0) {
        self.links = links
        self.biolinks = biolinks
        self.qrCodes = qrCodes
        self.projects = projects
        self.domains = domains
        self.pixels = pixels
        self.totalClicks = totalClicks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        links = try c.decodeIfPresent(Int.self, forKey: .links) ?? 0
        biolinks = try c.decodeIfPresent(Int.self, forKey: .biolinks) ?? 0
        qrCodes = try c.decodeIfPresent(Int.self, forKey: .qrCodes) ?? 0
        projects = try c.decodeIfPresent(Int.self, forKey: .projects) ?? 0
        domains = try c.decodeIfPresent(Int.self, forKey: .domains) ?? 0
        pixels = try c.decodeIfPresent(Int.self, forKey: .pixels) ?? 0
        totalClicks = try c.decodeIfPresent(Int.self, forKey: .totalClicks) ?? 0
    }

    /// The web dashboard's "Resources" figure: everything the workspace
    /// holds, summed the same way.
    public var resources: Int { links + biolinks + qrCodes + projects + domains + pixels }

    /// True for a workspace with nothing in it yet.
    public var isEmpty: Bool { resources == 0 && totalClicks == 0 }
}

/// Helpers for the dashboard's 30-day series.
public enum DashboardTraffic {
    /// One row per UTC day from `from` through `through`, with the days the
    /// server left out (no traffic) filled with zeros, oldest first.
    ///
    /// `GET /statistics/all?type=overview` returns only days that had a
    /// visit, so a sparkline drawn straight from it would join distant days
    /// and hide the quiet ones.
    public static func daily(_ rows: [DailyTraffic], from: Date, through: Date) -> [DailyTraffic] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let byDay = Dictionary(rows.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let last = CardsiteJSON.dayString(through)

        var series: [DailyTraffic] = []
        var day = calendar.startOfDay(for: min(from, through))
        // Bounded so a reversed or absurd range can't loop for long.
        for _ in 0..<400 {
            let key = CardsiteJSON.dayString(day)
            series.append(byDay[key] ?? DailyTraffic(date: key, pageviews: 0, visitors: 0))
            if key >= last { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return series
    }
}
