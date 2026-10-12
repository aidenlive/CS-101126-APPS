import Foundation

/// Traffic for one resource or the whole workspace. The older
/// `dailyTraffic(linkID:…)` / `breakdown(linkID:…)` stay in `APIClient.swift`.
extension APIClient {
    /// Daily pageviews and visitors from `from` to `to`, both inclusive
    /// (UTC days). Days without traffic are absent; `[]` when there is none.
    public func trafficOverview(_ target: StatisticsTarget, from: Date, to: Date) async throws -> [DailyTraffic] {
        let rows: [DailyTraffic]? = try await sendOptional(.get, "api/v1/statistics/\(target.pathComponent)", query: [
            "type": "overview",
            "start_date": CardsiteJSON.dayString(from),
            "end_date": CardsiteJSON.dayString(to),
        ])
        return rows ?? []
    }

    /// Pageviews grouped by `dimension`, largest first (hours in hour
    /// order). `limit` applies to every dimension except `.hour`.
    public func trafficBreakdown(_ target: StatisticsTarget, by dimension: StatisticsDimension,
                                 from: Date, to: Date, limit: Int = 12) async throws -> [StatisticsRow] {
        let rows: [StatisticsRow]? = try await sendOptional(.get, "api/v1/statistics/\(target.pathComponent)", query: [
            "type": dimension.rawValue,
            "start_date": CardsiteJSON.dayString(from),
            "end_date": CardsiteJSON.dayString(to),
            "limit": String(limit),
        ])
        return rows ?? []
    }
}
