import Foundation
import Observation
import CardsiteKit

/// What the Library hub shows: the workspace's counts, for the type rows,
/// and the recently edited resources, for the shelf.
///
/// One load gathers both (`GET /dashboard`-style summary and
/// `GET /resources/recent`), so the hub appears whole. Like `HomeModel`, a
/// refresh keeps the last snapshot on screen and reports its own failure
/// separately. Owned by `MainView`, so switching tabs doesn't refetch.
@MainActor
@Observable
final class LibraryModel {
    struct Snapshot: Equatable {
        var summary: DashboardSummary
        var recent: [Resource]
    }

    /// How many tiles the shelf holds: more than Home's five, so it reads
    /// as a shelf to browse.
    nonisolated static let recentLimit = 12

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

        do {
            async let summary = client.dashboardSummary()
            async let recent = client.recentResources(limit: Self.recentLimit)
            state = .loaded(Snapshot(summary: try await summary, recent: try await recent))
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

    /// The count a hub row shows, where the summary has one.
    static func count(for destination: AppDestination, in summary: DashboardSummary) -> Int? {
        switch destination {
        case .pages: return summary.biolinks
        case .qrCodes: return summary.qrCodes
        case .projects: return summary.projects
        case .domains: return summary.domains
        case .pixels: return summary.pixels
        default: return nil
        }
    }
}

extension LibraryModel.Snapshot {
    /// Previews, and the shape the loading skeleton redacts.
    static let sample = LibraryModel.Snapshot(
        summary: HomeModel.Snapshot.sample.summary,
        recent: HomeModel.Snapshot.sample.recent
    )

    /// A workspace with nothing in it.
    static let empty = LibraryModel.Snapshot(summary: DashboardSummary(), recent: [])
}
