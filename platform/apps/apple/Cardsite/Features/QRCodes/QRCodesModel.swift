import Foundation
import Observation
import CardsiteKit

/// QR codes for the current workspace, and the server's list of QR types
/// (fetched once, shared by every builder opened in this session).
@MainActor
@Observable
final class QRCodesModel {
    let list: PagedListModel<QRCode>
    let client: APIClient
    var searchText = ""
    private(set) var types: Loadable<[QRCodeTypeInfo]> = .idle

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    init(client: APIClient) {
        self.client = client
        self.list = PagedListModel { page in try await client.qrCodes(page: page) }
    }

    /// For previews and tests: a list served by `fetch`, and preset types.
    init(client: APIClient, types: [QRCodeTypeInfo], fetch: @escaping @Sendable (Int) async throws -> Page<QRCode>) {
        self.client = client
        self.list = PagedListModel(fetch: fetch)
        self.types = .loaded(types)
    }

    /// Codes matching the search field: name, type or what the code encodes.
    /// The server's QR list takes no `search` parameter, so this filters the
    /// loaded pages.
    var visibleCodes: [QRCode] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return list.items }
        return list.items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || typeLabel(for: $0.type).localizedCaseInsensitiveContains(query)
                || ($0.target ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    func typeLabel(for type: String) -> String {
        types.value?.first { $0.value == type }?.label ?? QRCodeCatalog.fallbackLabel(type)
    }

    // MARK: Types

    func loadTypesIfNeeded() async {
        switch types {
        case .loaded, .loading: return
        case .idle, .failed: break
        }
        types = .loading
        do {
            types = .loaded(try await client.qrCodeTypes())
        } catch is CancellationError {
            types = .idle
        } catch {
            onError(error)
            types = .failed(error.asAPIError)
        }
    }

    // MARK: Writes

    func design(id: Int) async throws -> QRCodeDesign {
        do {
            return try await client.qrCodeDesign(id: id)
        } catch {
            onError(error)
            throw error
        }
    }

    func create(_ payload: QRCodePayload) async throws -> QRCodeDesign {
        do {
            let design = try await client.createQRCode(payload: payload)
            list.insert(design.summary)
            return design
        } catch {
            onError(error)
            throw error
        }
    }

    func update(id: Int, _ payload: QRCodePayload) async throws -> QRCodeDesign {
        do {
            let design = try await client.updateQRCode(id: id, payload: payload)
            list.replace(design.summary)
            return design
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ code: QRCode) async throws {
        do {
            try await client.deleteQRCode(id: code.id)
            list.remove(id: code.id)
        } catch {
            onError(error)
            throw error
        }
    }
}
