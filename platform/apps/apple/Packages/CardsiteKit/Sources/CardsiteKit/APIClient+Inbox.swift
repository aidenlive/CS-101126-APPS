import Foundation

/// The in-app inbox. The list reads `per_page`, which ``sendPage(_:page:query:)``
/// already sends.
public extension APIClient {

    func inboxNotifications(page: Int = 1) async throws -> Page<InboxNotification> {
        try await sendPage("api/v1/internal-notifications", page: page)
    }

    func inboxUnreadSummary() async throws -> InboxUnreadSummary {
        try await send(.get, "api/v1/internal-notifications/unread")
    }

    func markNotificationRead(id: Int) async throws {
        try await sendIgnoringBody(.post, "api/v1/internal-notifications/\(id)/read")
    }

    func markAllNotificationsRead() async throws {
        try await sendIgnoringBody(.post, "api/v1/internal-notifications/read-all")
    }
}
