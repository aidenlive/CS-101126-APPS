import Foundation

/// Workspace management. Every route but `/workspaces/activity` acts on the
/// workspace in the path, not on `X-Workspace-ID`; the server answers 404
/// both for an unknown id and for one the caller is not a member of.
public extension APIClient {

    /// Creates a shared workspace with the caller as owner. Draws on the
    /// plan's teams limit (``APIError/planLimit(limit:current:max:)``).
    func createWorkspace(name: String) async throws -> Workspace {
        try await send(.post, "api/v1/workspaces", body: ["name": name])
    }

    /// Owner only; personal workspaces keep their name.
    func renameWorkspace(id: Int, name: String) async throws -> Workspace {
        try await send(.put, "api/v1/workspaces/\(id)", body: ["name": name])
    }

    /// Owner only. Deletes everything in the workspace.
    func deleteWorkspace(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/workspaces/\(id)")
    }

    /// Any member but the owner.
    func leaveWorkspace(id: Int) async throws {
        try await sendIgnoringBody(.post, "api/v1/workspaces/\(id)/leave")
    }

    func workspaceMembers(workspaceID: Int) async throws -> [WorkspaceMember] {
        let list: [WorkspaceMember]? = try await sendOptional(.get, "api/v1/workspaces/\(workspaceID)/members")
        return list ?? []
    }

    /// Adds an existing Cardsite user by email. Admin or owner only; 404
    /// "No user with that email", 409 "User is already a member", 422 when
    /// the plan has no seat left.
    func addWorkspaceMember(workspaceID: Int, email: String, role: WorkspaceRole) async throws -> WorkspaceMember {
        try await send(.post, "api/v1/workspaces/\(workspaceID)/members",
                       body: ["email": email, "role": role.rawValue])
    }

    /// Between `.member` and `.admin`; the owner row is fixed.
    func updateWorkspaceMemberRole(workspaceID: Int, userID: Int, role: WorkspaceRole) async throws {
        try await sendIgnoringBody(.put, "api/v1/workspaces/\(workspaceID)/members/\(userID)",
                                   body: ["role": role.rawValue])
    }

    func removeWorkspaceMember(workspaceID: Int, userID: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/workspaces/\(workspaceID)/members/\(userID)")
    }

    /// The current workspace's recent activity, newest first. `limit` is
    /// capped at 100 by the server.
    func workspaceActivity(limit: Int = 25) async throws -> [WorkspaceActivityEvent] {
        let list: [WorkspaceActivityEvent]? = try await sendOptional(
            .get, "api/v1/workspaces/activity", query: ["limit": String(min(max(limit, 1), 100))]
        )
        return list ?? []
    }
}
