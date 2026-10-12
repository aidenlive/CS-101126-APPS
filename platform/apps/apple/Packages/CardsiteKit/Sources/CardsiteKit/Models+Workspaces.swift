import Foundation

// Workspaces, members and the activity feed. Shapes from fixtures 05 and
// 26z7–26z9 and the Go handlers (workspaces.go, activity.go).

public extension Workspace {
    /// The caller's role, or `.member` when the server left it out.
    var workspaceRole: WorkspaceRole { role.flatMap(WorkspaceRole.init(rawValue:)) ?? .member }
}

/// owner > admin > member, as `roleAtLeast` orders them on the server.
public enum WorkspaceRole: String, Sendable, Hashable, CaseIterable, Codable, Comparable {
    case member, admin, owner

    private var rank: Int {
        switch self {
        case .member: return 1
        case .admin: return 2
        case .owner: return 3
        }
    }

    public static func < (lhs: WorkspaceRole, rhs: WorkspaceRole) -> Bool { lhs.rank < rhs.rank }

    /// Admins and the owner add, re-role and remove members.
    public var canManageMembers: Bool { self >= .admin }
}

/// `GET /workspaces/{id}/members` (no pagination, `null` when empty).
public struct WorkspaceMember: Codable, Sendable, Hashable, Identifiable {
    public let workspaceID: Int
    public let userID: Int
    public let role: String
    public let name: String
    public let email: String
    public let createdAt: Date?

    public var id: Int { userID }
    public var workspaceRole: WorkspaceRole { WorkspaceRole(rawValue: role) ?? .member }
    /// The name, or the email when the name is blank.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? email : name
    }

    enum CodingKeys: String, CodingKey {
        case role, name, email
        case workspaceID = "workspace_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }

    public init(workspaceID: Int, userID: Int, role: String, name: String, email: String, createdAt: Date? = nil) {
        self.workspaceID = workspaceID
        self.userID = userID
        self.role = role
        self.name = name
        self.email = email
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try c.decodeIfPresent(Int.self, forKey: .workspaceID) ?? 0
        userID = try c.decode(Int.self, forKey: .userID)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? WorkspaceRole.member.rawValue
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        // The 201 from adding a member carries a zero `created_at`.
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// One row of `GET /workspaces/activity` for the current (`X-Workspace-ID`)
/// workspace. Actions seen: `comment.posted`, `block.created`,
/// `block.edited`, `resource.created`, `member.joined` (no subject).
public struct WorkspaceActivityEvent: Codable, Sendable, Hashable, Identifiable {
    public let action: String
    public let actorUserID: Int?
    /// Empty when the actor has since left or been deleted.
    public let actorName: String
    public let subjectType: String?
    public let subjectID: Int?
    public let linkID: Int?
    public let at: Date

    /// Rows carry no id; action, subject and time together are unique.
    public var id: String {
        "\(action)-\(subjectID.map(String.init) ?? "-")-\(actorUserID.map(String.init) ?? "-")-\(at.timeIntervalSince1970)"
    }

    enum CodingKeys: String, CodingKey {
        case action, at
        case actorUserID = "actor_user_id"
        case actorName = "actor_name"
        case subjectType = "subject_type"
        case subjectID = "subject_id"
        case linkID = "link_id"
    }

    public init(action: String, actorUserID: Int? = nil, actorName: String, subjectType: String? = nil,
                subjectID: Int? = nil, linkID: Int? = nil, at: Date) {
        self.action = action
        self.actorUserID = actorUserID
        self.actorName = actorName
        self.subjectType = subjectType
        self.subjectID = subjectID
        self.linkID = linkID
        self.at = at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        actorUserID = try c.decodeIfPresent(Int.self, forKey: .actorUserID)
        actorName = try c.decodeIfPresent(String.self, forKey: .actorName) ?? ""
        subjectType = try c.decodeIfPresent(String.self, forKey: .subjectType)
        subjectID = try c.decodeIfPresent(Int.self, forKey: .subjectID)
        linkID = try c.decodeIfPresent(Int.self, forKey: .linkID)
        at = try c.decode(Date.self, forKey: .at)
    }
}
