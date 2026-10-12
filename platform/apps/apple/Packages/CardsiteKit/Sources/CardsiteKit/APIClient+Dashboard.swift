import Foundation

/// The Home dashboard and quick search. Workspace traffic comes from
/// ``trafficOverview(_:from:to:)`` with `.all` (APIClient+Statistics.swift).
extension APIClient {
    /// `GET /statistics`: counts and total clicks for the current workspace
    /// (fixture 20a). The older ``summary()`` decodes a subset of it.
    public func dashboardSummary() async throws -> DashboardSummary {
        try await send(.get, "api/v1/statistics")
    }

    /// `GET /resources/recent`: the most recently edited resources of every
    /// type, newest first (fixture 20d). The server takes 1…50 and answers
    /// anything else with its default of 5. Rows carry `lifecycle_state: ""`,
    /// which ``Resource/isLapsing`` reads as unknown.
    public func recentResources(limit: Int = 5) async throws -> [Resource] {
        let clamped = min(max(limit, 1), 50)
        let rows: [Resource]? = try await sendOptional(.get, "api/v1/resources/recent",
                                                       query: ["limit": String(clamped)])
        return rows ?? []
    }

    /// Short links in the current workspace whose address or destination
    /// contains `text`, at most `limit` of them.
    ///
    /// Sent as `GET /links?search=`, never `/spotlight`, which searches every
    /// account. As of 2026-10-12 the server ignores `search` (handlers/links.go
    /// reads only `page` and `results_per_page`), so the first 100 links are
    /// filtered here; once the API honours the parameter, the same call
    /// narrows server-side with no change.
    public func searchLinks(matching text: String, limit: Int = 8) async throws -> [Resource] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        let page: Page<Resource> = try await sendPage("api/v1/links", page: 1, query: [
            "search": query,
            "results_per_page": "100",
        ])
        let matches = page.items.filter { link in
            !link.isBioPage
                && (link.slug.localizedCaseInsensitiveContains(query)
                    || (link.destination ?? "").localizedCaseInsensitiveContains(query))
        }
        return Array(matches.prefix(limit))
    }
}
