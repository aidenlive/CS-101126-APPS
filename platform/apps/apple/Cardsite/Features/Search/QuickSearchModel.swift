import Foundation
import Observation
import CardsiteKit

/// One query over everything the user can reach: destinations from the
/// registry, create actions, and the workspace's short links.
///
/// Shared by the ⌘K palette (iPad and Mac) and Home's search field
/// (iPhone). Links come from `GET /links?search=`, never `/spotlight`,
/// which searches every account.
@MainActor
@Observable
final class QuickSearchModel {
    var query = ""
    private(set) var links: Loadable<[Resource]> = .idle
    /// A search is in flight. Earlier results stay visible meanwhile.
    private(set) var isFetchingLinks = false
    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }

    /// Below this the link search doesn't run; the server's own spotlight
    /// uses the same floor.
    static let minimumLinkQuery = 2

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var destinations: [AppDestination] {
        AppDestination.allCases.filter { $0.matches(trimmedQuery) }
    }

    var actions: [CreateAction] {
        CreateAction.allCases.filter { $0.matches(trimmedQuery) }
    }

    var linkResults: [Resource] { links.value ?? [] }

    var isSearchingLinks: Bool { isFetchingLinks }

    /// True when the query is long enough to search links.
    var searchesLinks: Bool { trimmedQuery.count >= Self.minimumLinkQuery }

    /// Nothing matched anywhere, and no link search is still running.
    var hasNoResults: Bool {
        destinations.isEmpty && actions.isEmpty && linkResults.isEmpty && !isSearchingLinks
    }

    /// Searches links for the current query. Call it from
    /// `.task(id: query)`: typing cancels the previous call during its
    /// short debounce, so only the last keystroke reaches the server.
    func searchLinks() async {
        let text = trimmedQuery
        guard text.count >= Self.minimumLinkQuery else {
            links = .idle
            isFetchingLinks = false
            return
        }
        // Marked busy through the debounce too, so "no results" doesn't
        // flash before the search has run. A cancelled call leaves the flag
        // to the call that replaced it.
        isFetchingLinks = true
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }
        if links.value == nil { links = .loading }
        do {
            let found = try await client.searchLinks(matching: text, limit: 8)
            guard text == trimmedQuery else { return }
            links = .loaded(found)
            isFetchingLinks = false
        } catch is CancellationError {
        } catch {
            onError(error)
            links = .failed(error.asAPIError)
            isFetchingLinks = false
        }
    }

    func reset() {
        query = ""
        links = .idle
        isFetchingLinks = false
    }
}
