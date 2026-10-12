import Foundation

/// The short-link editor's endpoints. The original list/create/update/delete
/// calls stay in `APIClient.swift`.
extension APIClient {
    /// One page of short links. A non-empty `search` is sent as `search=`.
    ///
    /// Note: as of 2026-10-12 `GET /links` ignores `search` (handlers/links.go
    /// reads only `page` and `results_per_page`), so callers should still
    /// filter what they have loaded. The parameter is sent so the list
    /// narrows server-side as soon as the API honours it.
    public func links(page: Int, search: String?) async throws -> Page<Resource> {
        var query: [String: String] = [:]
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            query["search"] = search
        }
        return try await sendPage("api/v1/links", page: page, query: query)
    }

    /// The full link: settings, targeting, schedule, references.
    public func linkDetail(id: Int) async throws -> LinkDetail {
        try await send(.get, "api/v1/links/\(id)")
    }

    /// Saves the editor's state, then re-reads the link (the PUT response
    /// carries the pre-write timestamps, quirk 1).
    public func saveLink(id: Int, changes: LinkChanges) async throws -> LinkDetail {
        try await sendIgnoringBody(.put, "api/v1/links/\(id)", body: changes.body)
        return try await linkDetail(id: id)
    }

    /// Turns the address on or off and returns the fresh link.
    public func setLinkEnabled(id: Int, isEnabled: Bool) async throws -> LinkDetail {
        try await sendIgnoringBody(.put, "api/v1/links/\(id)", body: ["is_enabled": JSONValue.bool(isEnabled)])
        return try await linkDetail(id: id)
    }

    /// Copies a link to `<slug>-copy` (then `-copy-2`, …). The copy starts
    /// disabled with no clicks; settings, targeting and schedule come along.
    public func duplicateLink(id: Int) async throws -> Resource {
        try await send(.post, "api/v1/links/\(id)/duplicate")
    }
}
