import Foundation
import Observation
import CardsiteKit

/// Short links for the current workspace. Bio pages share the links table
/// on the server; they are listed on the Pages tab, so they're filtered out here.
@MainActor
@Observable
final class LinksModel {
    let list: PagedListModel<Resource>
    let client: APIClient
    var searchText = ""

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    init(client: APIClient) {
        self.client = client
        self.list = PagedListModel { page in try await client.links(page: page) }
    }

    /// Short links only, filtered by the search field (address or destination).
    var visibleLinks: [Resource] {
        let links = list.items.filter { !$0.isBioPage }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return links }
        return links.filter {
            $0.slug.localizedCaseInsensitiveContains(query)
                || ($0.destination ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    func create(slug: String, destination: URL) async throws -> Resource {
        do {
            let link = try await client.createLink(slug: slug, destination: destination)
            list.insert(link)
            return link
        } catch {
            onError(error)
            throw error
        }
    }

    func update(_ link: Resource, destination: URL? = nil, isEnabled: Bool? = nil) async throws -> Resource {
        do {
            let updated = try await client.updateLink(id: link.id, destination: destination, isEnabled: isEnabled)
            list.replace(updated)
            return updated
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ link: Resource) async throws {
        do {
            try await client.deleteLink(id: link.id)
            list.remove(id: link.id)
        } catch {
            onError(error)
            throw error
        }
    }
}

/// Traffic for one link over a window, for the detail screen.
@MainActor
@Observable
final class LinkTrafficModel {
    enum Window: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: return String(localized: "7 days")
            case .month: return String(localized: "30 days")
            case .quarter: return String(localized: "90 days")
            }
        }
    }

    struct Snapshot: Equatable {
        var days: [DailyTraffic]
        var referrers: [TrafficBreakdown]
        var countries: [TrafficBreakdown]

        var totalViews: Int { days.reduce(0) { $0 + $1.pageviews } }
        /// Daily unique visitors can't be summed across days (the same
        /// person counts once per day), so the period shows the daily average.
        var averageDailyVisitors: Int {
            guard !days.isEmpty else { return 0 }
            return Int((Double(days.reduce(0) { $0 + $1.visitors }) / Double(days.count)).rounded())
        }
    }

    private(set) var state: Loadable<Snapshot> = .idle
    var window: Window = .month
    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }

    private let client: APIClient
    private let linkID: Int

    init(client: APIClient, linkID: Int) {
        self.client = client
        self.linkID = linkID
    }

    func load() async {
        if state.value == nil { state = .loading }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(window.rawValue - 1), to: end) ?? end
        do {
            async let days = client.dailyTraffic(linkID: linkID, from: start, to: end)
            async let referrers = client.breakdown(linkID: linkID, by: .referrer, from: start, to: end)
            async let countries = client.breakdown(linkID: linkID, by: .country, from: start, to: end)
            state = .loaded(Snapshot(days: try await days, referrers: try await referrers, countries: try await countries))
        } catch is CancellationError {
        } catch {
            onError(error)
            state = .failed(error.asAPIError)
        }
    }
}
