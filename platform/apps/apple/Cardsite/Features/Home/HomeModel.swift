import Foundation
import Observation
import CardsiteKit

/// Everything Home shows: the workspace's counts, 30 days of traffic, the
/// recently edited resources and the best-performing address.
///
/// One load gathers it all, so the page appears whole rather than in
/// pieces. Like `PagedListModel`, a refresh keeps the last snapshot on
/// screen and reports its own failure separately.
@MainActor
@Observable
final class HomeModel {
    struct Snapshot: Equatable {
        var summary: DashboardSummary
        /// One row per day, oldest first, zero-filled.
        var traffic: [DailyTraffic]
        var recent: [Resource]
        /// The short link or bio page with the most clicks, if any has one.
        var top: Resource?

        var clicksInWindow: Int { traffic.reduce(0) { $0 + $1.pageviews } }

        /// Daily visitors can't be summed across days (a returning visitor
        /// counts once per day), so the period shows the daily average, as
        /// link statistics do.
        var averageDailyVisitors: Int {
            guard !traffic.isEmpty else { return 0 }
            return Int((Double(traffic.reduce(0) { $0 + $1.visitors }) / Double(traffic.count)).rounded())
        }

        var hasTraffic: Bool { traffic.contains { $0.pageviews > 0 || $0.visitors > 0 } }
    }

    /// The window the stats row covers, as on the web.
    nonisolated static let windowDays = 30

    private(set) var state: Loadable<Snapshot> = .idle
    private(set) var refreshError: APIError?
    private(set) var isRefreshing = false
    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// For previews: a model that starts in `state` and never fetches
    /// until refreshed.
    init(client: APIClient, state: Loadable<Snapshot>) {
        self.client = client
        self.state = state
    }

    var snapshot: Snapshot? { state.value }

    func loadIfNeeded() async {
        if case .idle = state { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        if state.value == nil { state = .loading }
        isRefreshing = true
        defer { isRefreshing = false }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(Self.windowDays - 1), to: end) ?? end
        do {
            async let summary = client.dashboardSummary()
            async let traffic = client.trafficOverview(.all, from: start, to: end)
            async let recent = client.recentResources(limit: 5)
            // The web picks the top performer from the first page of each
            // list; the API has no "top" query.
            async let links = client.links(page: 1)
            async let pages = client.bioPages(page: 1)

            let snapshot = Snapshot(
                summary: try await summary,
                traffic: DashboardTraffic.daily(try await traffic, from: start, through: end),
                recent: try await recent,
                top: Self.topPerformer(in: try await links.items + pages.items)
            )
            state = .loaded(snapshot)
            refreshError = nil
        } catch is CancellationError {
            if case .loading = state { state = .idle }
        } catch {
            let apiError = error.asAPIError
            onError(apiError)
            if state.value == nil {
                state = .failed(apiError)
            } else {
                refreshError = apiError
            }
        }
    }

    func dismissRefreshError() { refreshError = nil }

    /// The most-clicked resource, or nil when nothing has a click yet:
    /// a "top performer" with no traffic would be a claim without evidence.
    static func topPerformer(in resources: [Resource]) -> Resource? {
        guard let best = resources.max(by: { $0.clicks < $1.clicks }), best.clicks > 0 else { return nil }
        return best
    }
}

extension HomeModel.Snapshot {
    /// Sample data for previews, and the shape the loading skeleton redacts.
    static let sample: HomeModel.Snapshot = {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(HomeModel.windowDays - 1), to: end) ?? end
        let curve = [3, 5, 4, 8, 6, 9, 12, 10, 7, 11, 14, 13, 18, 16, 12, 15, 21, 19, 17, 24,
                     22, 20, 26, 23, 28, 25, 31, 27, 34, 30]
        var days = DashboardTraffic.daily([], from: start, through: end)
        for index in days.indices {
            let views = curve[index % curve.count]
            days[index] = DailyTraffic(date: days[index].date, pageviews: views, visitors: max(1, views * 2 / 3))
        }
        let now = Date()
        let recent = [
            Resource(id: 31, type: LinkKind.shortLink, slug: "spring-menu", destination: "https://example.com/menu/spring",
                     clicks: 1_284, updatedAt: now.addingTimeInterval(-1_800)),
            Resource(id: 30, type: LinkKind.bioPage, slug: "ada", destination: nil,
                     clicks: 642, updatedAt: now.addingTimeInterval(-7_200)),
            Resource(id: 28, type: LinkKind.shortLink, slug: "launch-day", destination: "https://example.com/blog/launch",
                     clicks: 97, updatedAt: now.addingTimeInterval(-86_400)),
            Resource(id: 27, type: "vcard", slug: "ada-card", destination: nil,
                     clicks: 12, updatedAt: now.addingTimeInterval(-3 * 86_400)),
        ]
        return HomeModel.Snapshot(
            summary: DashboardSummary(links: 18, biolinks: 2, qrCodes: 6, projects: 3, domains: 1, totalClicks: 12_480),
            traffic: days,
            recent: recent,
            top: recent.first
        )
    }()

    /// A workspace with nothing in it.
    static let empty = HomeModel.Snapshot(summary: DashboardSummary(), traffic: [], recent: [], top: nil)
}
