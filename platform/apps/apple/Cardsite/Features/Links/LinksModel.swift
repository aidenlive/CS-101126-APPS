import Foundation
import Observation
import Synchronization
import CardsiteKit

/// Short links for the current workspace, plus the reference data their
/// editor's pickers need.
///
/// Search: the text is sent as `search=` on every page request (see
/// `APIClient.links(page:search:)`), and the loaded rows are also filtered
/// locally by address and destination, because the API currently ignores
/// the parameter. Either way the list shows only matches.
@MainActor
@Observable
final class LinksModel {
    let list: PagedListModel<Resource>
    let client: APIClient
    /// Targeting vocabulary, domains, projects, splash pages, plan capabilities.
    let options: ResourceOptionsModel

    var searchText = "" {
        didSet { query.set(searchText) }
    }

    /// Links whose enabled switch is mid-request.
    private(set) var togglingIDs: Set<Int> = []

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet {
            list.onError = onError
            options.onError = onError
        }
    }

    @ObservationIgnored private let query: SearchQuery

    init(client: APIClient, options: ResourceOptionsModel? = nil) {
        let query = SearchQuery()
        self.client = client
        self.query = query
        self.options = options ?? ResourceOptionsModel(client: client)
        self.list = PagedListModel { page in
            try await client.links(page: page, search: query.value)
        }
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

    /// The list row's switch. Throws so the caller can say what went wrong.
    func setEnabled(_ link: Resource, _ isEnabled: Bool) async throws {
        guard !togglingIDs.contains(link.id) else { return }
        togglingIDs.insert(link.id)
        defer { togglingIDs.remove(link.id) }
        _ = try await update(link, isEnabled: isEnabled)
    }

    /// Copies a link; the copy starts switched off at `<slug>-copy`.
    func duplicate(_ link: Resource) async throws -> Resource {
        do {
            let copy = try await client.duplicateLink(id: link.id)
            list.insert(copy)
            return copy
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

    /// Keeps the list row in step with a link saved in the editor.
    func didSave(_ detail: LinkDetail) {
        list.replace(detail.resource)
    }
}

/// The search text, readable from the list's `@Sendable` page fetch.
private final class SearchQuery: Sendable {
    private let storage = Mutex("")

    var value: String { storage.withLock { $0 } }

    func set(_ text: String) {
        storage.withLock { $0 = text }
    }
}
