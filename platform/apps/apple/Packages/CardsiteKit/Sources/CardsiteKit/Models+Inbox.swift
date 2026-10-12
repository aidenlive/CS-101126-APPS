import Foundation

// The in-app inbox (`/internal-notifications`). Shapes from fixtures 26s–26x
// and models/internal_notification.go.

public struct InboxNotification: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    public let description: String?
    /// A web path such as `/dashboard`, or an absolute URL. Optional.
    public let url: String?
    /// A Font Awesome class name from the web (`fas fa-bell`).
    public let icon: String?
    /// `system`, `admin`, …
    public let fromWho: String?
    public var isRead: Bool
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, url, icon
        case fromWho = "from_who"
        case isRead = "is_read"
        case createdAt = "datetime"
    }

    public init(id: Int, title: String, description: String? = nil, url: String? = nil, icon: String? = nil,
                fromWho: String? = "system", isRead: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.icon = icon
        self.fromWho = fromWho
        self.isRead = isRead
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        fromWho = try c.decodeIfPresent(String.self, forKey: .fromWho)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    /// The address to open: absolute as sent, or a web path resolved against
    /// `webBase` (the dashboard host). Nil when there is nothing to open or
    /// the scheme is not http(s).
    public func destination(relativeTo webBase: URL) -> URL? {
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let resolved = URL(string: raw, relativeTo: webBase)?.absoluteURL
        guard let resolved, let scheme = resolved.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return resolved
    }
}

/// `GET /internal-notifications/unread`: the latest 5 unread and the total.
public struct InboxUnreadSummary: Codable, Sendable, Hashable {
    public let notifications: [InboxNotification]
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case notifications
        case unreadCount = "unread_count"
    }

    public init(notifications: [InboxNotification], unreadCount: Int) {
        self.notifications = notifications
        self.unreadCount = unreadCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `null` when nothing is unread (quirk 13).
        notifications = try c.decodeIfPresent([InboxNotification].self, forKey: .notifications) ?? []
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}
