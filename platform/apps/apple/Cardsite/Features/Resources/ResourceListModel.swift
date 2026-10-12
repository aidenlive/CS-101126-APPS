import Foundation
import Observation
import Synchronization
import CardsiteKit

/// One row of a resource list: a link-backed resource, or a splash page.
enum ResourceItem: Identifiable, Sendable, Equatable, Hashable {
    case link(ManagedResource)
    case splash(SplashPage)

    var id: Int {
        switch self {
        case .link(let resource): return resource.id
        case .splash(let page): return page.id
        }
    }

    var link: ManagedResource? {
        if case .link(let resource) = self { return resource }
        return nil
    }

    var splash: SplashPage? {
        if case .splash(let page) = self { return page }
        return nil
    }

    /// Splash pages have no switch, so they read as always on.
    var isEnabled: Bool { link?.isEnabled ?? true }
    var isLapsing: Bool { link?.isLapsing ?? false }
    var clicks: Int? { link?.clicks }
    var slug: String? { link?.slug }

    /// The row's lead line: the thing's own name where it has one.
    var name: String {
        switch self {
        case .splash(let page):
            return page.displayName
        case .link(let resource):
            switch resource.resourceType {
            case .vcard:
                let name = resource.vcard.fullName
                return name.isEmpty ? "/" + resource.slug : name
            case .event:
                let name = resource.event.name.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? "/" + resource.slug : name
            case .paymentLink:
                let title = resource.paymentLink.title.trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? "/" + resource.slug : title
            case .file:
                let file = resource.file.fileName
                return file.isEmpty ? "/" + resource.slug : file
            case .staticPage, .none:
                return "/" + resource.slug
            }
        }
    }

    /// The detail under the name: what tells two rows apart at a glance.
    var detail: String {
        switch self {
        case .splash(let page):
            let unlock = String(localized: "Unlocks after \(page.linkUnlockSeconds) s")
            return page.title.isEmpty ? unlock : "\(page.title) · \(unlock)"
        case .link(let resource):
            switch resource.resourceType {
            case .vcard:
                let card = resource.vcard
                let parts = [card.jobTitle, card.company].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                return parts.isEmpty ? card.email : parts.joined(separator: " · ")
            case .event:
                let event = resource.event
                var parts: [String] = []
                if let start = event.startDate {
                    var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
                    style.timeZone = TimeZone(identifier: event.timezone) ?? .current
                    parts.append(start.formatted(style))
                }
                let location = event.location.trimmingCharacters(in: .whitespaces)
                if !location.isEmpty { parts.append(location) }
                return parts.joined(separator: " · ")
            case .paymentLink:
                return Self.host(of: resource.destination) ?? String(localized: "No checkout URL")
            case .file:
                return resource.file.forceDownload ? String(localized: "Downloads") : String(localized: "Opens in the browser")
            case .staticPage:
                return resource.staticPage.isSite ? String(localized: "Site (ZIP)") : String(localized: "Single page")
            case .none:
                return ""
            }
        }
    }

    /// Search matches the name, the detail, the address and the type's key fields.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        var haystack = [name, detail]
        switch self {
        case .splash(let page):
            haystack += [page.title, page.description]
        case .link(let resource):
            haystack.append(resource.slug)
            switch resource.resourceType {
            case .vcard:
                let card = resource.vcard
                haystack += [card.email, card.company, card.jobTitle, card.fullName]
            case .event:
                haystack += [resource.event.name, resource.event.location]
            case .paymentLink:
                haystack.append(resource.destination ?? "")
            case .file:
                haystack.append(resource.file.fileName)
            case .staticPage, .none:
                break
            }
        }
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func host(of raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let url = URL(string: raw), let host = url.host() else { return raw }
        let path = url.path()
        let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return path.isEmpty || path == "/" ? trimmedHost : trimmedHost + path
    }
}

/// One kind's resources for the current workspace, the reference data its
/// editor's pickers need, and the row actions.
///
/// Search: the text is sent as `search=` and the loaded rows are also
/// filtered locally, because the list endpoints don't read it yet.
@MainActor
@Observable
final class ResourceListModel {
    let kind: ResourceKind
    let client: APIClient
    let list: PagedListModel<ResourceItem>
    /// Domains (for addresses) and plan capabilities (for the gate).
    let options: ResourceOptionsModel

    var searchText = "" {
        didSet { query.set(searchText) }
    }

    /// Rows whose switch is mid-request.
    private(set) var togglingIDs: Set<Int> = []

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet {
            list.onError = onError
            options.onError = onError
        }
    }

    @ObservationIgnored private let query: ResourceSearchQuery

    init(kind: ResourceKind, client: APIClient, options: ResourceOptionsModel? = nil) {
        let query = ResourceSearchQuery()
        self.kind = kind
        self.client = client
        self.query = query
        self.options = options ?? ResourceOptionsModel(client: client)
        self.list = PagedListModel { page in
            if let type = kind.linkType {
                let result = try await client.managedResources(type, page: page, search: query.value)
                return Page(items: result.items.map(ResourceItem.link), meta: result.meta)
            }
            let result = try await client.splashPages(page: page)
            return Page(items: result.items.map(ResourceItem.splash), meta: result.meta)
        }
    }

    /// The loaded rows, filtered by the search field.
    var visibleItems: [ResourceItem] {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return list.items }
        return list.items.filter { $0.matches(text) }
    }

    /// The current copy of a row, for headers that outlive a toggle.
    func current(_ item: ResourceItem) -> ResourceItem {
        list.items.first { $0.id == item.id } ?? item
    }

    // MARK: Addresses

    /// The host an address lives on: its custom domain, else card.site.
    func host(for domainID: Int?, defaultHost: String) -> String {
        guard let domainID, let domain = options.domains.first(where: { $0.id == domainID }) else { return defaultHost }
        return domain.host
    }

    /// The public URL of a row with an address.
    func publicURL(for item: ResourceItem, addresses: AddressBook) -> URL? {
        guard let resource = item.link, !resource.slug.isEmpty else { return nil }
        if let domainID = resource.domainID, let domain = options.domains.first(where: { $0.id == domainID }) {
            return domain.url(for: resource.slug)
        }
        return addresses.url(for: resource.slug)
    }

    /// "card.site/spring-menu", for display.
    func displayAddress(for item: ResourceItem, addresses: AddressBook) -> String? {
        guard let resource = item.link else { return nil }
        return "\(host(for: resource.domainID, defaultHost: addresses.publicHost))/\(resource.slug)"
    }

    // MARK: Row actions

    /// The row's switch. Throws so the caller can say what went wrong.
    func setEnabled(_ item: ResourceItem, _ isEnabled: Bool) async throws {
        guard let type = kind.linkType, !togglingIDs.contains(item.id) else { return }
        togglingIDs.insert(item.id)
        defer { togglingIDs.remove(item.id) }
        do {
            let fresh = try await client.setManagedResourceEnabled(type, id: item.id, isEnabled: isEnabled)
            list.replace(.link(fresh))
        } catch {
            onError(error)
            throw error
        }
    }

    /// Copies a vCard, event or payment link; the copy starts switched off.
    func duplicate(_ item: ResourceItem) async throws -> ResourceItem {
        do {
            let copy = ResourceItem.link(try await client.duplicateManagedResource(id: item.id))
            list.insert(copy)
            return copy
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ item: ResourceItem) async throws {
        do {
            if let type = kind.linkType {
                try await client.deleteManagedResource(type, id: item.id)
            } else {
                try await client.deleteSplashPage(id: item.id)
            }
            list.remove(id: item.id)
        } catch {
            onError(error)
            throw error
        }
    }

    /// A fresh copy from the server, for an editor that has been open a while.
    func fetch(_ item: ResourceItem) async throws -> ResourceItem {
        do {
            let fresh: ResourceItem
            if let type = kind.linkType {
                fresh = .link(try await client.managedResource(type, id: item.id))
            } else {
                fresh = .splash(try await client.splashPage(id: item.id))
            }
            list.replace(fresh)
            return fresh
        } catch {
            onError(error)
            throw error
        }
    }

    /// Keeps the list in step with an editor's save: a new item goes first.
    func didSave(_ item: ResourceItem) {
        if list.items.contains(where: { $0.id == item.id }) {
            list.replace(item)
        } else if list.state.value != nil {
            list.insert(item)
        }
    }
}

/// The search text, readable from the list's `@Sendable` page fetch.
private final class ResourceSearchQuery: Sendable {
    private let storage = Mutex("")

    var value: String { storage.withLock { $0 } }

    func set(_ text: String) {
        storage.withLock { $0 = text }
    }
}
