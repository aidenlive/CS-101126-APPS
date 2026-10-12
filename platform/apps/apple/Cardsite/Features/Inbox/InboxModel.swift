import Foundation
import Observation
import CardsiteKit

/// The in-app inbox and its unread count.
///
/// The shell owns one for the whole session, so the tab or sidebar item can
/// show a badge, and injects it:
///
///     @State private var inbox: InboxModel   // InboxModel(client: client)
///     …
///     .environment(inbox)
///     .badge(inbox.unreadCount)
///     .task { await inbox.pollUnreadCount() }
///
/// ``InboxScreen`` uses the injected model when there is one and makes its
/// own otherwise.
@MainActor
@Observable
final class InboxModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, unread
        var id: String { rawValue }
    }

    let list: PagedListModel<InboxNotification>
    let client: APIClient
    var filter: Filter = .all
    /// Unread notifications across the account, from the server.
    private(set) var unreadCount = 0
    private(set) var isMarkingAll = false

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    /// How often ``pollUnreadCount()`` asks. The web polls the same way
    /// until the realtime stream lands (wave 3).
    static let pollInterval: Duration = .seconds(60)

    init(client: APIClient) {
        self.client = client
        self.list = PagedListModel { page in try await client.inboxNotifications(page: page) }
    }

    var visibleItems: [InboxNotification] {
        switch filter {
        case .all: return list.items
        case .unread: return list.items.filter { !$0.isRead }
        }
    }

    /// The badge count, plus the list when it has been opened. Quiet on
    /// failure: a badge that can't refresh keeps its last value.
    func refresh() async {
        await refreshUnreadCount()
        if case .idle = list.state { return }
        await list.refresh()
    }

    func refreshUnreadCount() async {
        do {
            unreadCount = try await client.inboxUnreadSummary().unreadCount
        } catch is CancellationError {
        } catch {
            onError(error)
        }
    }

    /// Refreshes the count now and then every ``pollInterval`` until the
    /// calling task is cancelled (attach it with `.task`).
    func pollUnreadCount() async {
        while !Task.isCancelled {
            await refreshUnreadCount()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    func markRead(_ notification: InboxNotification) async throws {
        guard !notification.isRead else { return }
        do {
            try await client.markNotificationRead(id: notification.id)
            var read = notification
            read.isRead = true
            list.replace(read)
            unreadCount = max(0, unreadCount - 1)
        } catch {
            onError(error)
            throw error
        }
    }

    func markAllRead() async throws {
        isMarkingAll = true
        defer { isMarkingAll = false }
        do {
            try await client.markAllNotificationsRead()
            for item in list.items where !item.isRead {
                var read = item
                read.isRead = true
                list.replace(read)
            }
            unreadCount = 0
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetch.
    func seed(_ items: [InboxNotification]) {
        for item in items.reversed() { list.insert(item) }
        unreadCount = items.filter { !$0.isRead }.count
    }
}
