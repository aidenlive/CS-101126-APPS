import Foundation
import Observation
import CoreLocation
import CardsiteKit

/// The builder screen: loads a code to edit, keeps a live server preview of
/// the draft, picks a link for dynamic codes, and saves.
@MainActor
@Observable
final class QRCodeBuilderModel {
    enum Mode: Equatable {
        case create(prefill: URL?)
        case edit(QRCode)
    }

    enum Phase: Equatable {
        case loading
        case ready
        case failed(APIError)
    }

    /// The live preview. `png` stays on screen while a newer one loads.
    struct Preview: Equatable {
        var png: Data?
        var embeddedData: String?
        var isLoading = false
        var error: APIError?
    }

    let mode: Mode
    var draft = QRCodeDraft()
    private(set) var original = QRCodeDraft()
    private(set) var phase: Phase = .ready
    private(set) var preview = Preview()
    private(set) var links: Loadable<[Resource]> = .idle
    private(set) var isSaving = false
    private(set) var isGeocoding = false

    var nameError: String?
    var linkError: String?
    var formError: String?
    var geocodeError: String?

    private let codes: QRCodesModel
    private let addresses: AddressBook
    /// The payload the current preview image was made from.
    @ObservationIgnored private var previewedPayload: QRCodePayload?

    init(mode: Mode, codes: QRCodesModel, addresses: AddressBook) {
        self.mode = mode
        self.codes = codes
        self.addresses = addresses
        switch mode {
        case .create(let prefill):
            let initial = prefill.map { QRCodeDraft(prefill: $0, publicHost: addresses.publicHost) } ?? QRCodeDraft()
            draft = initial
            original = initial
        case .edit(let code):
            // The list row's image, until the full record arrives.
            preview = Preview(png: code.pngData)
            phase = .loading
        }
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var hasChanges: Bool { phase == .ready && draft != original }

    var types: Loadable<[QRCodeTypeInfo]> { codes.types }

    var typeLabel: String { codes.typeLabel(for: draft.type) }

    var fileName: String {
        let base = Slug.suggestion(from: draft.trimmedName)
        return (base.isEmpty ? "cardsite-qr" : base) + ".png"
    }

    // MARK: Loading

    func load() async {
        await codes.loadTypesIfNeeded()
        guard case .edit(let code) = mode, phase != .ready else { return }
        phase = .loading
        do {
            let design = try await codes.design(id: code.id)
            draft = QRCodeDraft(design: design)
            original = draft
            if let png = design.pngData {
                preview = Preview(png: png, embeddedData: design.embeddedData)
                previewedPayload = draft.payload
            }
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed(error.asAPIError)
        }
    }

    func retryTypes() async {
        await codes.loadTypesIfNeeded()
    }

    // MARK: Preview

    /// Debounced: call from `.task(id: draft.payload)`, which cancels the
    /// previous call on every edit, so only a pause of about 400 ms reaches
    /// the server.
    func refreshPreview() async {
        guard phase == .ready else { return }
        guard draft.hasContent else {
            preview = Preview()
            previewedPayload = nil
            return
        }
        let payload = draft.payload
        guard payload != previewedPayload || preview.png == nil else { return }
        preview.isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }
        await generate(payload)
    }

    /// Regenerates now, for the Retry button.
    func retryPreview() async {
        guard phase == .ready, draft.hasContent else { return }
        preview.isLoading = true
        await generate(draft.payload)
    }

    private func generate(_ payload: QRCodePayload) async {
        do {
            let result = try await codes.client.previewQRCode(payload)
            preview = Preview(png: result.pngData, embeddedData: result.embeddedData)
            previewedPayload = payload
        } catch is CancellationError {
            // A newer edit took over and owns the loading state.
        } catch {
            let apiError = error.asAPIError
            codes.onError(apiError)
            preview.isLoading = false
            preview.error = apiError
        }
    }

    // MARK: Type

    func selectType(_ type: String) {
        guard type != draft.type else { return }
        draft.selectType(type)
        linkError = nil
        formError = nil
        if type == QRCodeCatalog.dynamicURLType, let items = links.value {
            matchLink(in: items)
        }
    }

    // MARK: Dynamic links

    func loadLinksIfNeeded() async {
        guard draft.type == QRCodeCatalog.dynamicURLType else { return }
        switch links {
        case .loaded, .loading: return
        case .idle, .failed: break
        }
        links = .loading
        do {
            let page = try await codes.client.links()
            let items = page.items.filter { !$0.isBioPage }
            links = .loaded(items)
            matchLink(in: items)
        } catch is CancellationError {
            links = .idle
        } catch {
            codes.onError(error)
            links = .failed(error.asAPIError)
        }
    }

    func retryLinks() async {
        links = .idle
        await loadLinksIfNeeded()
    }

    /// The selected link, by `link_id` or by the encoded address.
    var selectedLinkID: Int? {
        get { draft.linkID }
        set { selectLink(id: newValue) }
    }

    func selectLink(id: Int?) {
        linkError = nil
        guard let id, let link = links.value?.first(where: { $0.id == id }),
              let url = addresses.url(for: link.slug) else {
            draft.linkID = nil
            return
        }
        draft.linkID = link.id
        draft.setString(url.absoluteString, for: "url")
    }

    /// The encoded address when it isn't one of the loaded links (a code made
    /// on the web with a typed URL, or a link on a later page).
    var unmatchedDynamicURL: String? {
        let url = draft.dynamicURL
        guard !url.isEmpty, draft.linkID == nil || links.value?.contains(where: { $0.id == draft.linkID }) == false else {
            return nil
        }
        return url
    }

    private func matchLink(in items: [Resource]) {
        if let id = draft.linkID, items.contains(where: { $0.id == id }) { return }
        let current = draft.dynamicURL
        if !current.isEmpty {
            if let match = items.first(where: { addresses.url(for: $0.slug)?.absoluteString == current }) {
                draft.linkID = match.id
            }
            return
        }
        // A new dynamic code starts on the newest link, as before.
        if let first = items.first { selectLink(id: first.id) }
    }

    func displayAddress(for link: Resource) -> String {
        addresses.display(for: link.slug)
    }

    // MARK: Location

    /// Fills latitude and longitude from a typed address. The address itself
    /// isn't stored: the code encodes `geo:lat,long`, as on the web.
    func findCoordinates(for address: String) async {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isGeocoding else { return }
        isGeocoding = true
        geocodeError = nil
        defer { isGeocoding = false }
        do {
            guard let coordinate = try await Self.coordinate(for: query) else {
                geocodeError = String(localized: "No place found for that address.")
                return
            }
            draft.setString(String(format: "%.6f", coordinate.latitude), for: "latitude")
            draft.setString(String(format: "%.6f", coordinate.longitude), for: "longitude")
        } catch is CancellationError {
        } catch {
            geocodeError = String(localized: "Couldn’t look up that address. Check your connection and try again.")
        }
    }

    /// Runs the geocoder off the main actor and returns plain numbers, so no
    /// non-Sendable placemark crosses back.
    nonisolated private static func coordinate(for address: String) async throws -> (latitude: Double, longitude: Double)? {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(address)
        guard let location = placemarks.first?.location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    // MARK: Save

    /// Creates or updates the code. Returns the saved row, or nil with
    /// ``nameError``, ``linkError`` or ``formError`` set.
    func save() async -> QRCode? {
        guard !isSaving, phase == .ready else { return nil }
        nameError = nil
        linkError = nil
        formError = nil
        if draft.trimmedName.isEmpty {
            nameError = String(localized: "Give the QR code a name so you can find it later.")
        }
        if draft.type == QRCodeCatalog.dynamicURLType, draft.dynamicURL.isEmpty {
            linkError = String(localized: "Choose a link.")
        } else if !draft.hasContent {
            formError = String(localized: "Fill in the details to encode.")
        }
        guard nameError == nil, linkError == nil, formError == nil else { return nil }

        isSaving = true
        defer { isSaving = false }
        do {
            let design: QRCodeDesign
            switch mode {
            case .create:
                design = try await codes.create(draft.payload)
            case .edit(let code):
                design = try await codes.update(id: code.id, draft.payload)
            }
            original = draft
            return design.summary
        } catch {
            formError = error.asAPIError.localizedDescription
            return nil
        }
    }
}
