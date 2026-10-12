import Foundation
import Observation
import CardsiteKit

/// Bio pages for the current workspace, plus what every page editor shares:
/// the block catalogue, the plan's capabilities and the feature flags.
@MainActor
@Observable
final class PagesModel {
    let list: PagedListModel<BioPage>
    let client: APIClient
    var searchText = ""
    /// A page to open in the editor, set from outside the Pages screen (a
    /// "New Bio Page" command, a search result). The screen consumes it.
    var openRequest: BioPage.ID?

    /// The 85 block types and their field specs, loaded once.
    private(set) var blockTypes: Loadable<[BlockType]> = .idle
    /// What the plan includes. Nil until known, or when it couldn't be
    /// read, in which case nothing is locked and the server has the last word.
    private(set) var capabilities: PlanCapabilities?
    private(set) var featureFlags: Set<String> = []

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    init(client: APIClient) {
        self.client = client
        self.list = PagedListModel { page in try await client.bioPageList(page: page) }
    }

    /// Pages matching the search field (name or address). The API takes no
    /// search parameter for bio pages, so this filters what is loaded.
    var visiblePages: [BioPage] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return list.items }
        return list.items.filter {
            $0.slug.localizedCaseInsensitiveContains(query)
                || ($0.title ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Shared catalogue

    func blockType(_ type: String) -> BlockType? {
        blockTypes.value?.first { $0.type == type }
    }

    /// True when the plan grants `capability`, or when that isn't known.
    func allows(_ capability: String) -> Bool {
        capabilities?.includes(capability) ?? true
    }

    func isFlagOn(_ key: String) -> Bool {
        featureFlags.contains(key)
    }

    func loadCatalogIfNeeded() async {
        switch blockTypes {
        case .idle, .failed: await loadCatalog()
        case .loading, .loaded: return
        }
    }

    func loadCatalog() async {
        if blockTypes.value == nil { blockTypes = .loading }
        async let types = client.blockTypes()
        async let capabilities = client.planCapabilities()
        async let flags = client.bioFeatureFlags()
        do {
            blockTypes = .loaded(try await types)
        } catch is CancellationError {
            if case .loading = blockTypes { blockTypes = .idle }
        } catch {
            onError(error)
            if blockTypes.value == nil { blockTypes = .failed(error.asAPIError) }
        }
        // Capabilities and flags only narrow what is offered; when they
        // can't be read the editor stays usable and the server still checks.
        do {
            self.capabilities = try await capabilities
        } catch {
            onError(error)
        }
        do {
            featureFlags = try await flags
        } catch {
            onError(error)
        }
    }

    // MARK: Writes

    func create(slug: String, title: String) async throws -> BioPage {
        do {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = try await client.createBioPage(slug: slug, title: trimmed.isEmpty ? nil : trimmed)
            list.insert(page)
            return page
        } catch {
            onError(error)
            throw error
        }
    }

    func setEnabled(_ page: BioPage, _ isEnabled: Bool) async throws {
        do {
            let updated = try await client.updateBioPage(id: page.id, BioPageChanges(isEnabled: isEnabled))
            list.replace(updated)
        } catch {
            onError(error)
            throw error
        }
    }

    func duplicate(_ page: BioPage) async throws -> BioPage {
        do {
            let copy = try await client.duplicateBioPage(id: page.id)
            list.insert(copy)
            return copy
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ page: BioPage) async throws {
        do {
            try await client.deleteBioPage(id: page.id)
            list.remove(id: page.id)
        } catch {
            onError(error)
            throw error
        }
    }

    /// An editor changed the page; keep its row in step.
    func pageDidChange(_ page: BioPage) {
        list.replace(page)
    }
}

#if DEBUG
extension PagesModel {
    /// Fills the model without a network, for previews.
    func seedForPreview(pages: [BioPage], types: [BlockType], capabilities: PlanCapabilities?, flags: Set<String> = []) {
        for page in pages.reversed() { list.insert(page) }
        blockTypes = .loaded(types)
        self.capabilities = capabilities
        featureFlags = flags
    }
}
#endif

extension PagesModel {
    /// Keys from apps/web/src/lib/featureFlags.ts.
    enum Flag {
        /// Shows the settings that save but reach no page yet.
        static let unwiredSettings = "bio_page_unwired_settings"
    }

    /// Capability keys from apps/api/internal/models/capability.go.
    enum Capability {
        static let premiumBlocks = BlockType.premiumCapability
        static let targeting = PlanCapabilities.targetingKey
    }
}
