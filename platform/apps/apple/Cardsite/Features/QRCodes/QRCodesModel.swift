import Foundation
import Observation
import CardsiteKit

@MainActor
@Observable
final class QRCodesModel {
    let list: PagedListModel<QRCode>
    let client: APIClient
    var searchText = ""

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    init(client: APIClient) {
        self.client = client
        self.list = PagedListModel { page in try await client.qrCodes(page: page) }
    }

    var visibleCodes: [QRCode] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return list.items }
        return list.items.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.target ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    func create(name: String, url: URL, linkID: Int?) async throws -> QRCode {
        do {
            let code = try await client.createQRCode(name: name, url: url, linkID: linkID)
            list.insert(code)
            return code
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
