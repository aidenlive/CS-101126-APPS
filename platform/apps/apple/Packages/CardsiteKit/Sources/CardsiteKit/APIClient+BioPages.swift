import Foundation

/// Bio pages, their blocks, and what the editor reads beside them.
///
/// Shapes are from the Go handlers (`handlers/biolinks.go`,
/// `handlers/biolink_blocks.go`, `link_duplicate.go`) and the live fixtures
/// 24a–24j.
extension APIClient {

    // MARK: Pages

    /// `GET /biolinks`. The list carries `settings` but not a trustworthy
    /// `directory_is_enabled` (it is always `false` here).
    public func bioPageList(page: Int = 1) async throws -> Page<BioPage> {
        try await sendPage("api/v1/biolinks", page: page)
    }

    /// `GET /biolinks/{id}` → the page and its blocks.
    public func bioPage(id: Int) async throws -> BioPageDocument {
        try await send(.get, "api/v1/biolinks/\(id)")
    }

    /// `POST /biolinks`. A taken address is a 409 (``APIError/conflict(title:message:lastEditor:)``),
    /// a full plan a 422 (``APIError/planLimit(limit:current:max:)``).
    public func createBioPage(slug: String, title: String? = nil) async throws -> BioPage {
        var settings: [String: JSONValue] = [:]
        if let title, !title.isEmpty { settings["title"] = .string(title) }
        let body: [String: JSONValue] = ["url": .string(slug), "settings": .object(settings)]
        return try await send(.post, "api/v1/biolinks", body: body)
    }

    /// `PUT /biolinks/{id}`. Setting audience rules on a plan without
    /// `targeting_is_enabled` is a 422 (``APIError/planCapability(label:)``).
    public func updateBioPage(id: Int, _ changes: BioPageChanges) async throws -> BioPage {
        try await send(.put, "api/v1/biolinks/\(id)", body: changes.body)
    }

    /// `DELETE /biolinks/{id}`; the blocks go with it.
    public func deleteBioPage(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/biolinks/\(id)")
    }

    /// `POST /links/{id}/duplicate`. The copy lands at `<slug>-copy` (then
    /// `-copy-2`, …), switched off and unlisted, with every block copied.
    public func duplicateBioPage(id: Int) async throws -> BioPage {
        try await send(.post, "api/v1/links/\(id)/duplicate")
    }

    // MARK: Blocks

    /// `GET /biolink-blocks/types`: every block type with its field specs.
    public func blockTypes() async throws -> [BlockType] {
        let list: [BlockType]? = try await sendOptional(.get, "api/v1/biolink-blocks/types")
        return list ?? []
    }

    /// `POST /biolink-blocks`. A premium type on a plan without
    /// `premium_blocks` is a 422 (``APIError/planCapability(label:)``).
    public func createBlock(pageID: Int, type: String, settings: [String: JSONValue],
                            locationURL: String? = nil, order: Int? = nil) async throws -> BioBlock {
        var body: [String: JSONValue] = [
            "link_id": .int(pageID),
            "type": .string(type),
            "settings": .object(settings),
        ]
        if let locationURL, !locationURL.isEmpty { body["location_url"] = .string(locationURL) }
        if let order { body["order"] = .int(order) }
        return try await send(.post, "api/v1/biolink-blocks", body: body)
    }

    /// `PUT /biolink-blocks/{id}` with the `version` the block was loaded at.
    ///
    /// `settings`, when given, replaces the stored object whole. Fields left
    /// nil are not sent. A stale `version` throws ``BlockConflictError``.
    public func updateBlock(id: Int, version: Int, settings: [String: JSONValue]? = nil,
                            locationURL: String? = nil, isEnabled: Bool? = nil) async throws -> BioBlock {
        var body: [String: JSONValue] = ["version": .int(version)]
        if let settings { body["settings"] = .object(settings) }
        if let locationURL { body["location_url"] = .string(locationURL) }
        if let isEnabled { body["is_enabled"] = .bool(isEnabled) }
        do {
            return try await send(.put, "api/v1/biolink-blocks/\(id)", body: body)
        } catch APIError.conflict(let title, _, let lastEditor) {
            throw BlockConflictError(serverTitle: title, lastEditor: lastEditor)
        }
    }

    /// `POST /biolink-blocks/order`: the page's block ids, top to bottom.
    public func reorderBlocks(_ ids: [Int]) async throws {
        try await sendIgnoringBody(.post, "api/v1/biolink-blocks/order", body: ["biolink_block_ids": ids])
    }

    /// `DELETE /biolink-blocks/{id}`.
    public func deleteBlock(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/biolink-blocks/\(id)")
    }

    // MARK: Beside the editor

    /// Every pixel in the workspace (`GET /pixels`, all pages).
    public func bioPixels() async throws -> [BioPixel] {
        var all: [BioPixel] = []
        var page = 1
        while true {
            let result: Page<BioPixel> = try await sendPage("api/v1/pixels", page: page, query: ["results_per_page": "100"])
            all.append(contentsOf: result.items)
            // Twenty pages of a hundred is far past any real workspace; the
            // bound keeps a server that misreports `total` from looping.
            guard result.hasMore, page < 20 else { break }
            page += 1
        }
        return all
    }

    /// `GET /pixels/types`, for which providers can emit on a bio page.
    public func bioPixelTypes() async throws -> [BioPixelType] {
        let list: [BioPixelType]? = try await sendOptional(.get, "api/v1/pixels/types")
        return list ?? []
    }

    /// `GET /feature-flags/evaluate`: the flag keys switched on for this user.
    public func bioFeatureFlags() async throws -> Set<String> {
        let keys: [String]? = try await sendOptional(.get, "api/v1/feature-flags/evaluate")
        return Set(keys ?? [])
    }
}
