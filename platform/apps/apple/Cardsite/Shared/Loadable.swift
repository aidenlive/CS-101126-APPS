import Foundation
import Observation
import CardsiteKit

/// The four states every remote list goes through.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: APIError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

extension Error {
    /// Every thrown error as an APIError, so views have one type to render.
    var asAPIError: APIError {
        (self as? APIError) ?? .transport(localizedDescription)
    }
}

/// A paginated, refreshable list of items from one endpoint.
///
/// Keeps loaded items visible while refreshing, and keeps a refresh failure
/// separate from the first-load failure, so a dropped connection never
/// blanks a list the user was reading.
@MainActor
@Observable
final class PagedListModel<Item: Identifiable & Sendable & Equatable> {
    private(set) var state: Loadable<[Item]> = .idle
    private(set) var refreshError: APIError?
    private(set) var isLoadingMore = false
    private var nextPage = 1
    private(set) var hasMore = false
    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }

    private let fetch: @Sendable (Int) async throws -> Page<Item>

    init(fetch: @escaping @Sendable (Int) async throws -> Page<Item>) {
        self.fetch = fetch
    }

    var items: [Item] { state.value ?? [] }

    func loadIfNeeded() async {
        if case .idle = state { await refresh() }
    }

    func refresh() async {
        if state.value == nil { state = .loading }
        do {
            let page = try await fetch(1)
            state = .loaded(page.items)
            hasMore = page.hasMore
            nextPage = 2
            refreshError = nil
        } catch is CancellationError {
            if case .loading = state { state = .idle }
        } catch {
            let apiError = error.asAPIError
            onError(apiError)
            if state.value == nil {
                state = .failed(apiError)
            } else {
                refreshError = apiError
            }
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, var current = state.value else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(nextPage)
            let known = Set(current.map(\.id))
            current.append(contentsOf: page.items.filter { !known.contains($0.id) })
            state = .loaded(current)
            hasMore = page.hasMore
            nextPage += 1
        } catch is CancellationError {
        } catch {
            refreshError = error.asAPIError
            onError(error)
        }
    }

    func dismissRefreshError() { refreshError = nil }

    // Local edits after a successful write.
    func insert(_ item: Item) {
        var current = state.value ?? []
        current.removeAll { $0.id == item.id }
        current.insert(item, at: 0)
        state = .loaded(current)
    }

    func replace(_ item: Item) {
        guard var current = state.value, let index = current.firstIndex(where: { $0.id == item.id }) else { return }
        current[index] = item
        state = .loaded(current)
    }

    func remove(id: Item.ID) {
        guard var current = state.value else { return }
        current.removeAll { $0.id == id }
        state = .loaded(current)
    }
}
