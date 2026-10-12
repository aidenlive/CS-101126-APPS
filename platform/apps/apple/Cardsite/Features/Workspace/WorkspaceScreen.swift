import SwiftUI
import StudioKit
import CardsiteKit

/// The root for the registry: its own navigation stack.
struct WorkspaceScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            WorkspaceView(client: app.client, onError: { [app] in app.handle($0) })
        }
    }
}

/// The current workspace: storage, members (invite, role, remove), activity,
/// and rename / delete (owner) or leave (everyone else). Switching between
/// workspaces is the shell's switcher; this screen creates new ones.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.switchWorkspace) private var switchWorkspace
    @State private var model: WorkspaceModel
    @State private var sheet: Sheet? = nil
    @State private var confirm: Confirmation? = nil
    @State private var actionError: ActionError? = nil

    struct ActionError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum Sheet: Identifiable {
        case create, rename(String), invite
        var id: String {
            switch self {
            case .create: return "create"
            case .rename: return "rename"
            case .invite: return "invite"
            }
        }
    }

    enum Confirmation: Identifiable {
        case delete(Workspace), leave(Workspace), remove(WorkspaceMember)
        var id: String {
            switch self {
            case .delete(let workspace): return "delete-\(workspace.id)"
            case .leave(let workspace): return "leave-\(workspace.id)"
            case .remove(let member): return "remove-\(member.userID)"
            }
        }
    }

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: WorkspaceModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: WorkspaceModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .background(Color.studioBg)
            .pageHeadNavigationTitle(model.snapshot.map { title(for: $0.workspace) } ?? String(localized: "Workspace"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sheet = .create
                    } label: {
                        Label("New Workspace", systemImage: "plus")
                    }
                }
            }
            .task { [model] in await model.loadIfNeeded() }
            // Reloads when the shell's switcher changes workspace.
            .onChange(of: app.workspaceScope) { _, _ in Task { await model.refresh() } }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .create:
                    WorkspaceNameSheet(mode: .create) { name in
                        let created = try await model.create(name: name)
                        await select(created.id)
                    }
                case .rename(let current):
                    WorkspaceNameSheet(mode: .rename(current)) { name in
                        try await model.rename(to: name)
                    }
                case .invite:
                    InviteMemberSheet { email, role in
                        try await model.invite(email: email, role: role)
                    }
                }
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                titleVisibility: .visible,
                presenting: confirm
            ) { confirmation in
                switch confirmation {
                case .delete:
                    Button("Delete Workspace", role: .destructive) { Task { await perform(confirmation) } }
                case .leave:
                    Button("Leave", role: .destructive) { Task { await perform(confirmation) } }
                case .remove(let member):
                    Button("Remove \(member.email)", role: .destructive) { Task { await perform(confirmation) } }
                }
            } message: { confirmation in
                switch confirmation {
                case .delete:
                    Text("Every link, QR code and resource in it is permanently deleted.")
                case .leave:
                    Text("You lose access to everything in it until someone adds you again.")
                case .remove:
                    Text("They lose access to everything in this workspace.")
                }
            }
            .alert(
                actionError?.title ?? "",
                isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
                presenting: actionError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
    }

    private var confirmTitle: String {
        switch confirm {
        case .delete(let workspace): return String(localized: "Delete workspace “\(workspace.name)”?")
        case .leave(let workspace): return String(localized: "Leave workspace “\(workspace.name)”?")
        case .remove(let member): return String(localized: "Remove \(member.email) from this workspace?")
        case nil: return ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ListSkeletonView(style: .textRows, head: Self.placeholderHead)
        case .failed(let error):
            ErrorStateView(error: error, head: Self.placeholderHead) { [model] in await model.refresh() }
        case .loaded(let snapshot):
            form(snapshot)
        }
    }

    /// The head before the workspace is known: the page keeps its anatomy
    /// while it loads or when it can't load.
    private static let placeholderHead = ListPageHeadContent(
        kicker: String(localized: "Account · Collaboration"),
        title: String(localized: "Workspace")
    )

    // MARK: Content

    private func form(_ snapshot: Snapshot) -> some View {
        let workspace = snapshot.workspace
        let role = workspace.workspaceRole
        return Form {
            ListPageHead(
                kicker: String(localized: "Account · Collaboration"),
                title: title(for: workspace),
                description: workspace.isPersonal
                    ? String(localized: "Your private workspace. Create a shared workspace to collaborate.")
                    : String(localized: "Members of this workspace see and manage everything in it.")
            ) {
                StudioStatusPill(roleTitle(role), tone: role == .owner ? .success : .neutral)
            }

            if let error = model.refreshError {
                RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                    .studioClearRow()
            }

            Section {
                LabeledContent {
                    Text((workspace.storageBytes ?? 0).formatted(.byteCount(style: .file)))
                        .monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text("Storage used")
                        Text("Everything this workspace’s files, pages and bundles hold.")
                            .studioText(.uiSm)
                            .studioMuted()
                    }
                }
            }
            .studioRowBackground()

            membersSection(snapshot, role: role)
            activitySection(snapshot)

            if !workspace.isPersonal {
                Section {
                    if role == .owner {
                        Button("Rename Workspace…") { sheet = .rename(workspace.name) }
                        Button("Delete Workspace…", role: .destructive) { confirm = .delete(workspace) }
                    } else {
                        Button("Leave Workspace…", role: .destructive) { confirm = .leave(workspace) }
                    }
                } footer: {
                    if role == .owner {
                        Text("Deleting a workspace removes every link, QR code and resource in it. This can’t be undone.")
                    }
                }
                .studioRowBackground()
            }
        }
        .studioForm()
        .refreshable { [model] in await model.refresh() }
    }

    typealias Snapshot = WorkspaceModel.Snapshot

    @ViewBuilder
    private func membersSection(_ snapshot: Snapshot, role: WorkspaceRole) -> some View {
        let workspace = snapshot.workspace
        let canManage = role.canManageMembers && !workspace.isPersonal
        Section {
            ForEach(snapshot.members.sorted(by: memberOrder)) { member in
                let isSelf = member.userID == app.user?.id
                let isEditable = canManage && member.workspaceRole != .owner && !isSelf
                MemberRow(member: member, isSelf: isSelf) {
                    if isEditable {
                        Menu {
                            Picker("Role", selection: Binding(
                                get: { member.workspaceRole },
                                set: { newRole in Task { await setRole(newRole, for: member) } }
                            )) {
                                Text("Member").tag(WorkspaceRole.member)
                                Text("Admin").tag(WorkspaceRole.admin)
                            }
                            Divider()
                            Button(role: .destructive) { confirm = .remove(member) } label: {
                                Label("Remove…", systemImage: "person.badge.minus")
                            }
                        } label: {
                            HStack(spacing: StudioSpace.s1) {
                                Text(roleTitle(member.workspaceRole))
                                Image(systemName: "chevron.up.chevron.down")
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                            }
                            .studioText(.uiSm)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .accessibilityLabel(Text("Role for \(member.displayName): \(roleTitle(member.workspaceRole))"))
                    } else {
                        StudioStatusPill(roleTitle(member.workspaceRole),
                                         tone: member.workspaceRole == .owner ? .success : .neutral)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if isEditable {
                        Button(role: .destructive) { confirm = .remove(member) } label: {
                            Label("Remove", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
            if canManage {
                Button {
                    sheet = .invite
                } label: {
                    Label("Add Member…", systemImage: "person.badge.plus")
                }
            }
        } header: {
            Text("Members")
        } footer: {
            if workspace.isPersonal {
                Text("Your personal workspace is private — it has no other members. Create a shared workspace to collaborate with your team.")
            } else if canManage {
                Text("Admins can also add, re-role and remove members. Members create and edit resources.")
            }
        }
        .studioRowBackground()
    }

    @ViewBuilder
    private func activitySection(_ snapshot: Snapshot) -> some View {
        Section("Activity") {
            if let error = snapshot.activityError {
                FormRetryRow(
                    message: String(localized: "Couldn’t load the activity feed. \(error.localizedDescription)"),
                    systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle"
                ) { [model] in
                    await model.refresh()
                }
            } else if snapshot.activity.isEmpty {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Nothing has happened yet")
                        .studioText(.ui)
                    Text("Comments, edits and new resources from everyone in this workspace show up here.")
                        .studioText(.uiSm)
                        .studioMuted()
                }
                .padding(.vertical, StudioSpace.s1)
            } else {
                ForEach(snapshot.activity) { event in
                    HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                        Image(systemName: event.systemImage)
                            .foregroundStyle(Color.studioText3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: StudioSpace.s1) {
                            Text(event.sentence)
                                .studioText(.ui)
                            RelativeTimeText(date: event.at)
                                .studioText(.uiSm)
                                .studioMuted()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .studioRowBackground()
    }

    // MARK: Helpers

    private func title(for workspace: Workspace) -> String {
        workspace.isPersonal ? String(localized: "Personal workspace") : workspace.name
    }

    private func roleTitle(_ role: WorkspaceRole) -> String {
        switch role {
        case .owner: return String(localized: "Owner")
        case .admin: return String(localized: "Admin")
        case .member: return String(localized: "Member")
        }
    }

    private func memberOrder(_ lhs: WorkspaceMember, _ rhs: WorkspaceMember) -> Bool {
        if lhs.workspaceRole != rhs.workspaceRole { return lhs.workspaceRole > rhs.workspaceRole }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func select(_ workspaceID: Int?) async {
        if let switchWorkspace {
            await switchWorkspace(workspaceID)
        } else {
            await model.client.setWorkspace(workspaceID)
        }
        await model.refresh()
    }

    private func setRole(_ role: WorkspaceRole, for member: WorkspaceMember) async {
        guard role != member.workspaceRole else { return }
        do {
            try await model.setRole(role, for: member)
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t change the role"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func perform(_ confirmation: Confirmation) async {
        confirm = nil
        do {
            switch confirmation {
            case .delete:
                try await model.delete()
                await select(nil)
            case .leave:
                try await model.leave()
                await select(nil)
            case .remove(let member):
                try await model.remove(member)
            }
            Haptics.success()
        } catch {
            let title: String
            switch confirmation {
            case .delete: title = String(localized: "Couldn’t delete the workspace")
            case .leave: title = String(localized: "Couldn’t leave the workspace")
            case .remove: title = String(localized: "Couldn’t remove the member")
            }
            actionError = ActionError(title: title, message: error.asAPIError.localizedDescription)
        }
    }
}

/// Initial, name (with "you"), email; the trailing slot holds the role.
private struct MemberRow<Trailing: View>: View {
    let member: WorkspaceMember
    let isSelf: Bool
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Text(String(member.displayName.prefix(1)).uppercased())
                .studioText(.ui)
                .foregroundStyle(Color.studioText2)
                .frame(width: StudioSpace.s8, height: StudioSpace.s8)
                .background(Circle().fill(Color.studioSurface3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                HStack(spacing: StudioSpace.s1) {
                    Text(verbatim: member.displayName)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(1)
                    if isSelf {
                        Text("(you)")
                            .studioText(.uiSm)
                            .studioMuted()
                    }
                }
                if member.displayName != member.email {
                    Text(verbatim: member.email)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: StudioSpace.s2)
            trailing()
        }
        .padding(.vertical, StudioSpace.s1)
    }
}

// MARK: - Sheets

/// Create a workspace, or rename the current one.
private struct WorkspaceNameSheet: View {
    enum Mode { case create, rename(String) }

    let mode: Mode
    let submit: @MainActor (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String? = nil
    @State private var isSaving = false

    private var isCreate: Bool { if case .create = mode { return true } else { return false } }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Workspace name", text: $name, prompt: Text("Acme Marketing"))
                        .onSubmit { Task { await save() } }
                } footer: {
                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        if isCreate {
                            Text("A shared space — everyone you add sees and manages its resources.")
                        }
                        FormErrorText(message: error)
                    }
                }
                .studioRowBackground()
            }
            .studioForm()
            .navigationTitle(isCreate ? "Create Workspace" : "Rename Workspace")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isCreate ? "Create" : "Save") { Task { await save() } }
                            .disabled(trimmed.isEmpty || trimmed.count > 128)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if case .rename(let current) = mode, name.isEmpty { name = current }
            }
        }
        .presentationDetents([.medium])
        .cardsiteSheet(.form)
    }

    private func save() async {
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await submit(trimmed)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

/// Invite an existing Cardsite user by their account email.
private struct InviteMemberSheet: View {
    let submit: @MainActor (String, WorkspaceRole) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role: WorkspaceRole = .member
    @State private var error: String? = nil
    @State private var isSaving = false

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email, prompt: Text(verbatim: "teammate@example.com"))
                        .textContentType(.emailAddress)
                        .plainEntry()
                        #if os(iOS) || os(visionOS)
                        .keyboardType(.emailAddress)
                        #endif
                } footer: {
                    Text("Invite an existing Cardsite user by their account email.")
                }
                .studioRowBackground()
                Section {
                    Picker("Role", selection: $role) {
                        Text("Member — create and edit resources").tag(WorkspaceRole.member)
                        Text("Admin — also manage members").tag(WorkspaceRole.admin)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Role")
                } footer: {
                    FormErrorText(message: error)
                }
                .studioRowBackground()
            }
            .studioForm()
            .navigationTitle("Add Member")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await save() } }
                            .disabled(!trimmed.contains("@"))
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .cardsiteSheet(.form)
    }

    private func save() async {
        guard trimmed.contains("@"), !isSaving else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await submit(trimmed, role)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Workspace") {
    let model = WorkspaceModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed(.init(
        workspace: Workspace(id: 339, name: "Studio", isPersonal: false, role: "owner", storageBytes: 18_400_000),
        members: [
            WorkspaceMember(workspaceID: 339, userID: 4, role: "owner", name: "Ada Lovelace", email: "ada@example.com"),
            WorkspaceMember(workspaceID: 339, userID: 7, role: "admin", name: "Grace Hopper", email: "grace@example.com"),
            WorkspaceMember(workspaceID: 339, userID: 9, role: "member", name: "", email: "alan@example.com"),
        ],
        activity: [
            WorkspaceActivityEvent(action: "resource.created", actorName: "Grace Hopper", subjectType: "vcard",
                                   subjectID: 25, at: .now.addingTimeInterval(-3_600)),
            WorkspaceActivityEvent(action: "block.edited", actorName: "Ada Lovelace", subjectType: "email_collector",
                                   subjectID: 9, at: .now.addingTimeInterval(-86_400)),
            WorkspaceActivityEvent(action: "member.joined", actorName: "", at: .now.addingTimeInterval(-172_800)),
        ]
    ))
    return NavigationStack { WorkspaceView(model: model) }
        .environment(AppModel.preview())
}
#endif
