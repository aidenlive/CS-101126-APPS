import Foundation
import Observation
import CardsiteKit

/// Traffic for one resource or the whole workspace over 7, 30 or 90 days,
/// with one breakdown dimension at a time.
///
/// The overview and the breakdown load independently: changing the
/// dimension refetches only the breakdown. Loaded data stays on screen while
/// a newer range loads, and a failed refresh keeps it with a banner, the same
/// way `PagedListModel` treats lists.
@MainActor
@Observable
final class StatisticsModel {
    enum Range: Int, CaseIterable, Identifiable, Hashable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }

        /// "7D", the web's segment label.
        var shortTitle: String {
            switch self {
            case .week: return String(localized: "7D")
            case .month: return String(localized: "30D")
            case .quarter: return String(localized: "90D")
            }
        }

        var accessibilityTitle: String {
            String(localized: "Last \(rawValue) days")
        }
    }

    /// The overview for one range, with every day present (days without
    /// traffic are zero), oldest first.
    struct Overview: Equatable {
        let days: [DailyTraffic]
        let start: Date
        let end: Date

        var pageviews: Int { days.reduce(0) { $0 + $1.pageviews } }
        /// Summed per day, as the web does: a person who comes back on
        /// another day counts again.
        var visitors: Int { days.reduce(0) { $0 + $1.visitors } }
        var visitorShare: Double? { pageviews > 0 ? Double(visitors) / Double(pageviews) : nil }
        /// Pageviews per calendar day in the range.
        var dailyAverage: Int {
            days.isEmpty ? 0 : Int((Double(pageviews) / Double(days.count)).rounded())
        }
        var peak: DailyTraffic? {
            days.filter { $0.pageviews > 0 }.max { $0.pageviews < $1.pageviews }
        }
        var isEmpty: Bool { pageviews == 0 }
    }

    let target: StatisticsTarget
    var range: Range = .month
    var dimension: StatisticsDimension = .country

    private(set) var overview: Loadable<Overview> = .idle
    private(set) var breakdown: Loadable<[StatisticsRow]> = .idle
    private(set) var isLoadingOverview = false
    private(set) var isLoadingBreakdown = false
    /// A refresh that failed while older data is still shown.
    private(set) var refreshError: APIError?

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }

    private let client: APIClient
    private let now: () -> Date
    /// False for previews, which show the data they were given.
    private let fetchesData: Bool

    init(client: APIClient, target: StatisticsTarget, now: @escaping () -> Date = { .now }) {
        self.client = client
        self.target = target
        self.now = now
        self.fetchesData = true
    }

    /// Preview seam: data already in hand.
    init(client: APIClient, target: StatisticsTarget, overview: Overview, breakdown: [StatisticsRow]) {
        self.client = client
        self.target = target
        self.now = { .now }
        self.fetchesData = false
        self.overview = .loaded(overview)
        self.breakdown = .loaded(breakdown)
    }

    var isRefreshing: Bool {
        (isLoadingOverview && overview.value != nil) || (isLoadingBreakdown && breakdown.value != nil)
    }

    /// Both, for pull-to-refresh and retry.
    func reload() async {
        async let overviewLoad: Void = loadOverview()
        async let breakdownLoad: Void = loadBreakdown()
        _ = await (overviewLoad, breakdownLoad)
    }

    func loadOverview() async {
        guard fetchesData else { return }
        let (start, end) = window()
        if overview.value == nil { overview = .loading }
        isLoadingOverview = true
        defer { isLoadingOverview = false }
        do {
            let rows = try await client.trafficOverview(target, from: start, to: end)
            overview = .loaded(Overview(days: Self.filled(rows, from: start, to: end), start: start, end: end))
            refreshError = nil
        } catch is CancellationError {
            if case .loading = overview { overview = .idle }
        } catch {
            fail(error, keeping: overview.value != nil) { self.overview = .failed($0) }
        }
    }

    func loadBreakdown() async {
        guard fetchesData else { return }
        let (start, end) = window()
        if breakdown.value == nil { breakdown = .loading }
        isLoadingBreakdown = true
        defer { isLoadingBreakdown = false }
        do {
            let rows = try await client.trafficBreakdown(target, by: dimension, from: start, to: end)
            breakdown = .loaded(rows)
            refreshError = nil
        } catch is CancellationError {
            if case .loading = breakdown { breakdown = .idle }
        } catch {
            fail(error, keeping: breakdown.value != nil) { self.breakdown = .failed($0) }
        }
    }

    /// Clears the breakdown when the dimension changes, so the old rows
    /// never read as the new dimension's.
    func dimensionChanged() {
        guard fetchesData else { return }
        breakdown = .idle
    }

    func dismissRefreshError() { refreshError = nil }

    private func fail(_ error: any Error, keeping hasData: Bool, setFailed: (APIError) -> Void) {
        let apiError = error.asAPIError
        onError(apiError)
        if hasData {
            refreshError = apiError
        } else {
            setFailed(apiError)
        }
    }

    /// The last `range` days, today included.
    private func window() -> (Date, Date) {
        let end = now()
        let start = Self.utc.date(byAdding: .day, value: -(range.rawValue - 1), to: end) ?? end
        return (start, end)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// One row per UTC day from `start` to `end`, zero where the server sent none.
    static func filled(_ rows: [DailyTraffic], from start: Date, to end: Date) -> [DailyTraffic] {
        let byDate = Dictionary(rows.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var days: [DailyTraffic] = []
        var cursor = utc.startOfDay(for: start)
        let last = utc.startOfDay(for: end)
        while cursor <= last {
            let key = CardsiteJSON.dayString(cursor)
            days.append(byDate[key] ?? DailyTraffic(date: key, pageviews: 0, visitors: 0))
            guard let next = utc.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}

// MARK: - Labels

extension StatisticsDimension {
    /// The web's names for the breakdown picker.
    var title: String {
        switch self {
        case .country: return String(localized: "Countries")
        case .continent: return String(localized: "Continents")
        case .city: return String(localized: "Cities")
        case .referrer: return String(localized: "Referrers")
        case .browser: return String(localized: "Browsers")
        case .operatingSystem: return String(localized: "Operating systems")
        case .deviceType: return String(localized: "Devices")
        case .utmSource: return String(localized: "UTM source")
        case .utmMedium: return String(localized: "UTM medium")
        case .utmCampaign: return String(localized: "UTM campaign")
        case .hour: return String(localized: "Hourly")
        }
    }

    var systemImage: String {
        switch self {
        case .country: return "flag"
        case .continent: return "globe.europe.africa"
        case .city: return "building.2"
        case .referrer: return "arrow.turn.down.right"
        case .browser: return "safari"
        case .operatingSystem: return "desktopcomputer"
        case .deviceType: return "iphone"
        case .utmSource, .utmMedium, .utmCampaign: return "tag"
        case .hour: return "clock"
        }
    }

    /// Hours read best in clock order; everything else is ranked.
    var isRanked: Bool { self != .hour }

    /// A row label for people: country names, "Direct" for no referrer,
    /// "14:00 UTC" for hours.
    func displayLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch self {
        case .referrer:
            return trimmed.isEmpty ? String(localized: "Direct") : trimmed
        case .country:
            guard !trimmed.isEmpty else { return String(localized: "Unknown") }
            return Locale.current.localizedString(forRegionCode: trimmed) ?? trimmed
        case .continent:
            return Self.continentNames[trimmed.uppercased()] ?? (trimmed.isEmpty ? String(localized: "Unknown") : trimmed)
        case .hour:
            guard let hour = Int(trimmed) else { return trimmed }
            return String(localized: "\(String(format: "%02d", hour)):00 UTC")
        case .deviceType, .browser, .operatingSystem:
            return trimmed.isEmpty ? String(localized: "Unknown") : trimmed.capitalized(with: .current)
        case .city, .utmSource, .utmMedium, .utmCampaign:
            return trimmed.isEmpty ? String(localized: "Unknown") : trimmed
        }
    }

    private static let continentNames: [String: String] = [
        "AF": String(localized: "Africa"),
        "AN": String(localized: "Antarctica"),
        "AS": String(localized: "Asia"),
        "EU": String(localized: "Europe"),
        "NA": String(localized: "North America"),
        "OC": String(localized: "Oceania"),
        "SA": String(localized: "South America"),
    ]
}

// MARK: - Previews

extension StatisticsModel.Overview {
    /// A month of plausible traffic, for previews.
    static func sample(days count: Int = 30, end: Date = .now) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: end) ?? end
        let days = (0..<count).compactMap { offset -> DailyTraffic? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let views = 40 + (offset * 7) % 55 + (offset % 7 == 5 ? 60 : 0)
            return DailyTraffic(date: CardsiteJSON.dayString(day), pageviews: views, visitors: views * 2 / 3)
        }
        return Self(days: days, start: start, end: end)
    }
}

extension StatisticsRow {
    static let sampleCountries: [StatisticsRow] = [
        StatisticsRow(label: "GB", pageviews: 812),
        StatisticsRow(label: "US", pageviews: 604),
        StatisticsRow(label: "DE", pageviews: 211),
        StatisticsRow(label: "FR", pageviews: 160),
        StatisticsRow(label: "", pageviews: 42),
    ]
}
