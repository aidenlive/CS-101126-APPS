import Foundation
import Observation
import CardsiteKit

/// One short link's editor: the saved link, the form being edited, the last
/// 30 days of traffic for the header, and save, toggle and delete.
@MainActor
@Observable
final class LinkDetailModel {
    struct RecentTraffic: Equatable {
        let pageviews: Int
        let visitors: Int
    }

    let linkID: Int
    /// The list row, shown in the header until the full link arrives.
    private(set) var seed: Resource
    private(set) var detail: LinkDetail?
    /// Set when the first load fails and nothing is on screen.
    private(set) var loadError: APIError?
    /// A reload failed while the editor still shows the earlier copy.
    private(set) var refreshError: APIError?
    var form: LinkForm?
    private(set) var savedForm: LinkForm?
    private(set) var errors: [LinkForm.Field: String] = [:]
    private(set) var formError: String?
    private(set) var isSaving = false
    private(set) var isTogglingEnabled = false
    private(set) var toggleError: String?
    private(set) var recent: RecentTraffic?
    /// Shown briefly after a save.
    private(set) var didJustSave = false

    private let links: LinksModel
    private var client: APIClient { links.client }
    /// False for previews, which show the link they were given.
    private let fetchesData: Bool

    init(seed: Resource, links: LinksModel) {
        self.linkID = seed.id
        self.seed = seed
        self.links = links
        self.fetchesData = true
    }

    /// Preview seam: a link already loaded.
    init(detail: LinkDetail, links: LinksModel, recent: RecentTraffic? = nil) {
        self.linkID = detail.id
        self.seed = detail.resource
        self.links = links
        self.fetchesData = false
        self.detail = detail
        let form = LinkForm(detail: detail)
        self.form = form
        self.savedForm = form
        self.recent = recent
    }

    var isDirty: Bool {
        guard let form, let savedForm else { return false }
        return form != savedForm
    }

    /// The header's state: the saved link once loaded, else the list row.
    var isEnabled: Bool { detail?.isEnabled ?? seed.isEnabled }
    var clicks: Int { detail?.clicks ?? seed.clicks }
    var isLapsing: Bool { detail?.isLapsing ?? seed.isLapsing }
    var slug: String { detail?.slug ?? seed.slug }
    var destination: String? { detail?.destination ?? seed.destination }

    // MARK: Loading

    func load() async {
        guard fetchesData else { return }
        async let traffic: Void = loadRecentTraffic()
        do {
            let detail = try await client.linkDetail(id: linkID)
            apply(detail, reseed: !isDirty)
            loadError = nil
            refreshError = nil
        } catch is CancellationError {
        } catch {
            links.onError(error)
            if self.detail == nil {
                loadError = error.asAPIError
            } else {
                refreshError = error.asAPIError
            }
        }
        await traffic
    }

    func dismissRefreshError() { refreshError = nil }

    private func loadRecentTraffic() async {
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end
        do {
            let days = try await client.trafficOverview(.link(linkID), from: start, to: end)
            recent = RecentTraffic(pageviews: days.reduce(0) { $0 + $1.pageviews },
                                   visitors: days.reduce(0) { $0 + $1.visitors })
        } catch is CancellationError {
        } catch {
            // The header shows "—"; the statistics screen has the full story.
            links.onError(error)
        }
    }

    /// A refetch must not clobber edits in progress (the web seeds once per load).
    private func apply(_ detail: LinkDetail, reseed: Bool) {
        self.detail = detail
        self.seed = detail.resource
        let fresh = LinkForm(detail: detail)
        if reseed || form == nil {
            form = fresh
        }
        savedForm = fresh
        links.didSave(detail)
    }

    // MARK: Editing

    func discard() {
        form = savedForm
        errors = [:]
        formError = nil
    }

    /// Validates, saves the whole link and re-reads it. Returns whether the
    /// server has the changes.
    @discardableResult
    func save() async -> Bool {
        guard let form, let savedForm, !isSaving else { return false }
        formError = nil
        errors = form.validate()
        guard errors.isEmpty else { return false }

        isSaving = true
        defer { isSaving = false }
        do {
            let detail = try await client.saveLink(id: linkID, changes: form.changes(comparedWith: savedForm))
            apply(detail, reseed: true)
            Haptics.success()
            didJustSave = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.didJustSave = false
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            links.onError(error)
            let apiError = error.asAPIError
            if let field = LinkForm.Field.owning(apiError) {
                errors[field] = field == .slug && apiError == .invalid("URL is required")
                    ? String(localized: "An address is required")
                    : apiError.localizedDescription
            } else {
                formError = apiError.localizedDescription
            }
            return false
        }
    }

    /// Drops the inline error of every field the user has since changed.
    func formChanged(from old: LinkForm?, to new: LinkForm?) {
        guard let old, let new, !errors.isEmpty || formError != nil else { return }
        formError = nil
        if old.slug != new.slug || old.domainID != new.domainID { errors[.slug] = nil }
        if old.destination != new.destination { errors[.destination] = nil }
        if old.isScheduled != new.isScheduled || old.start != new.start || old.end != new.end { errors[.schedule] = nil }
        if old.displayRules != new.displayRules { errors[.targeting] = nil }
        if old.password != new.password { errors[.password] = nil }
        if old.clicksLimitText != new.clicksLimitText { errors[.clicksLimit] = nil }
        if old.settings.expirationURL != new.settings.expirationURL { errors[.expirationURL] = nil }
    }

    // MARK: Actions

    func setEnabled(_ isEnabled: Bool) async {
        guard !isTogglingEnabled else { return }
        isTogglingEnabled = true
        toggleError = nil
        defer { isTogglingEnabled = false }
        do {
            let detail = try await client.setLinkEnabled(id: linkID, isEnabled: isEnabled)
            // Only the switch changed on the server, so edits in progress stay.
            apply(detail, reseed: !isDirty)
        } catch is CancellationError {
        } catch {
            links.onError(error)
            toggleError = error.asAPIError.localizedDescription
        }
    }

    func delete() async throws {
        try await links.delete(seed)
    }
}
