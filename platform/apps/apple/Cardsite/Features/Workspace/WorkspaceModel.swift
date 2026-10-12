import SwiftUI
import Observation
import CardsiteKit

/// Switches the app's current workspace. The shell injects the real one
/// (which also resets the list models):
///
///     .environment(\.switchWorkspace, SwitchWorkspaceAction { id in await app.selectWorkspace(id) })
///
/// Without it, the workspace screen sets the client's `X-Workspace-ID` itself.
struct SwitchWorkspaceAction: Sendable {
    let handler: @MainActor @Sendable (Int?) async -> Void

    init(_ handler: @escaping @MainActor @Sendable (Int?) async -> Void) {
        self.handler = handler
    }

    /// `nil` returns to the personal workspace.
    @MainActor
    func callAsFunction(_ workspaceID: Int?) async {
        await handler(workspaceID)
    }
}

extension EnvironmentValues {
    @Entry var switchWorkspace: SwitchWorkspaceAction? = nil
}

/// The current workspace: detail, members and recent activity.
///
/// "Current" is the client's `X-Workspace-ID`, or the personal workspace
/// when none is set, as the web resolves it.
@MainActor
@Observable
final class WorkspaceModel {
    struct Snapshot: Equatable {
        var workspace: Workspace
        var members: [WorkspaceMember]
        var activity: [WorkspaceActivityEvent]
        /// The feed is secondary: its failure doesn't hide the members.
        var activityError: APIError?
    }

    private(set) var state: Loadable<Snapshot> = .idle
    private(set) var refreshError: APIError?

    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
    }

    var snapshot: Snapshot? { state.value }

    func loadIfNeeded() async {
        if case .idle = state { await refresh() }
    }

    func refresh() async {
        if state.value == nil { state = .loading }
        let client = self.client
        do {
            let currentID = await client.workspaceID
            let all = try await client.workspaces()
            guard let workspace = all.first(where: { $0.id == currentID })
                    ?? all.first(where: \.isPersonal)
                    ?? all.first else {
                throw APIError.invalid(String(localized: "No workspace was found for this account."))
            }
            async let members = client.workspaceMembers(workspaceID: workspace.id)
            async let activity = Self.activityResult(client)
            let (loadedMembers, feed) = try await (members, activity)
            var snapshot = Snapshot(workspace: workspace, members: loadedMembers, activity: [], activityError: nil)
            switch feed {
            case .success(let events): snapshot.activity = events
            case .failure(let error): snapshot.activityError = error
            }
            state = .loaded(snapshot)
            refreshError = nil
        } catch is CancellationError {
            if case .loading = state { state = .idle }
        } catch {
            onError(error)
            if state.value == nil {
                state = .failed(error.asAPIError)
            } else {
                refreshError = error.asAPIError
            }
        }
    }

    private nonisolated static func activityResult(_ client: APIClient) async -> Result<[WorkspaceActivityEvent], APIError> {
        do {
            return .success(try await client.workspaceActivity(limit: 20))
        } catch {
            return .failure(error.asAPIError)
        }
    }

    func dismissRefreshError() { refreshError = nil }

    // MARK: Writes

    func rename(to name: String) async throws {
        guard var snapshot = state.value else { return }
        do {
            let renamed = try await client.renameWorkspace(id: snapshot.workspace.id, name: name)
            snapshot.workspace = Workspace(id: renamed.id, name: renamed.name, isPersonal: renamed.isPersonal,
                                           role: renamed.role ?? snapshot.workspace.role,
                                           storageBytes: snapshot.workspace.storageBytes)
            state = .loaded(snapshot)
        } catch {
            onError(error)
            throw error
        }
    }

    func delete() async throws {
        guard let workspace = state.value?.workspace else { return }
        do {
            try await client.deleteWorkspace(id: workspace.id)
        } catch {
            onError(error)
            throw error
        }
    }

    func leave() async throws {
        guard let workspace = state.value?.workspace else { return }
        do {
            try await client.leaveWorkspace(id: workspace.id)
        } catch {
            onError(error)
            throw error
        }
    }

    func create(name: String) async throws -> Workspace {
        do {
            return try await client.createWorkspace(name: name)
        } catch {
            onError(error)
            throw error
        }
    }

    func invite(email: String, role: WorkspaceRole) async throws {
        guard var snapshot = state.value else { return }
        do {
            let member = try await client.addWorkspaceMember(workspaceID: snapshot.workspace.id, email: email, role: role)
            snapshot.members.removeAll { $0.userID == member.userID }
            snapshot.members.append(member)
            state = .loaded(snapshot)
        } catch {
            onError(error)
            throw error
        }
    }

    func setRole(_ role: WorkspaceRole, for member: WorkspaceMember) async throws {
        guard var snapshot = state.value else { return }
        do {
            try await client.updateWorkspaceMemberRole(workspaceID: snapshot.workspace.id, userID: member.userID, role: role)
            if let index = snapshot.members.firstIndex(where: { $0.userID == member.userID }) {
                snapshot.members[index] = WorkspaceMember(workspaceID: member.workspaceID, userID: member.userID,
                                                          role: role.rawValue, name: member.name,
                                                          email: member.email, createdAt: member.createdAt)
            }
            state = .loaded(snapshot)
        } catch {
            onError(error)
            throw error
        }
    }

    func remove(_ member: WorkspaceMember) async throws {
        guard var snapshot = state.value else { return }
        do {
            try await client.removeWorkspaceMember(workspaceID: snapshot.workspace.id, userID: member.userID)
            snapshot.members.removeAll { $0.userID == member.userID }
            state = .loaded(snapshot)
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetch.
    func seed(_ snapshot: Snapshot) {
        state = .loaded(snapshot)
    }
}

extension WorkspaceActivityEvent {
    /// The web's sentences (`activity.action.*`).
    var sentence: String {
        let actor = actorName.isEmpty ? String(localized: "A former member") : actorName
        let subject = (subjectType ?? "").replacingOccurrences(of: "_", with: " ")
        switch action {
        case "comment.posted": return String(localized: "\(actor) commented")
        case "block.created": return String(localized: "\(actor) added a \(subject) block")
        case "block.edited": return String(localized: "\(actor) last edited a \(subject) block")
        case "resource.created": return String(localized: "\(actor) created a new \(subject)")
        case "member.joined": return String(localized: "\(actor) joined the workspace")
        default: return String(localized: "\(actor) did something here")
        }
    }

    var systemImage: String {
        switch action {
        case "comment.posted": return "text.bubble"
        case "block.created": return "plus.square.on.square"
        case "block.edited": return "pencil"
        case "resource.created": return "sparkles"
        case "member.joined": return "person.badge.plus"
        default: return "clock"
        }
    }
}
