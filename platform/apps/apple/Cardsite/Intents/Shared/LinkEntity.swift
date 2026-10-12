import Foundation
import AppIntents
import CardsiteKit

/// A short link, as Siri, Shortcuts and the widget configuration see it.
struct LinkEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Short Link")
    }
    static var defaultQuery: LinkEntityQuery { LinkEntityQuery() }

    let id: Int
    let slug: String
    /// `card.site/slug`, for display.
    let address: String
    /// `https://card.site/slug`.
    let shortURL: URL?
    let destination: String?
    /// All-time clicks when the entity was read.
    let clicks: Int

    init(_ link: Resource, addresses: AddressBook) {
        id = link.id
        slug = link.slug
        address = addresses.display(for: link.slug)
        shortURL = addresses.url(for: link.slug)
        destination = link.destination
        clicks = link.clicks
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(address)",
            subtitle: "\(destination ?? "")",
            image: DisplayRepresentation.Image(systemName: "link")
        )
    }
}

/// Finds links by ID (for saved shortcuts and widget configurations) and
/// by text (the picker's search field).
///
/// `GET /links` ignores `search=` as of 2026-10-12 (see
/// `APIClient.links(page:search:)`), so text matching filters the most
/// recent page here, the same way the Links screen does.
struct LinkEntityQuery: EntityStringQuery {
    func entities(for identifiers: [LinkEntity.ID]) async throws -> [LinkEntity] {
        let session = try await IntentSession.open()
        let addresses = session.addresses
        let found = try await session.run { client in
            try await withThrowingTaskGroup(of: LinkEntity?.self) { group in
                for id in identifiers {
                    group.addTask {
                        do {
                            return LinkEntity(try await client.link(id: id), addresses: addresses)
                        } catch APIError.invalid {
                            // 404: deleted, or in another workspace.
                            return nil
                        }
                    }
                }
                var entities: [LinkEntity] = []
                for try await entity in group {
                    if let entity { entities.append(entity) }
                }
                return entities
            }
        }
        // Keep the order the system asked in.
        return identifiers.compactMap { id in found.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [LinkEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let links = try await recentLinks()
        guard !needle.isEmpty else { return links }
        return links.filter {
            $0.address.localizedCaseInsensitiveContains(needle)
                || ($0.destination ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    func suggestedEntities() async throws -> [LinkEntity] {
        try await recentLinks()
    }

    /// The first page of short links (50), newest first.
    private func recentLinks() async throws -> [LinkEntity] {
        let session = try await IntentSession.open()
        let addresses = session.addresses
        let page = try await session.run { client in try await client.links(page: 1, search: nil) }
        return page.items
            .filter { $0.type == LinkKind.shortLink }
            .map { LinkEntity($0, addresses: addresses) }
    }
}
