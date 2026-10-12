import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Colour-coded folders for links: list, create, rename, recolour, delete.
/// The web's `/projects`.
@MainActor
@Observable
final class ProjectsModel {
    let list: PagedListModel<Project>
    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
        self.list = PagedListModel { page in try await client.projects(page: page) }
        self.list.onError = onError
    }

    /// Creates a project, or saves `project` with the new name and colour.
    func save(_ input: ProjectInput, editing project: Project?) async throws -> Project {
        do {
            if let project {
                let saved = try await client.updateProject(id: project.id, input)
                list.replace(saved)
                return saved
            }
            let created = try await client.createProject(input)
            list.insert(created)
            return created
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ project: Project) async throws {
        do {
            try await client.deleteProject(id: project.id)
            list.remove(id: project.id)
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetch. An empty list
    /// shows the empty state.
    func seed(_ projects: [Project]) {
        for project in projects.reversed() { list.insert(project) }
        if projects.isEmpty {
            list.insert(Project(id: -1, name: ""))
            list.remove(id: -1)
        }
    }
}

/// The registry's `.more` destination: stack-free.
struct ProjectsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ProjectsModel
    /// The editor sheet: a new project, or one to edit.
    @State private var editing: ProjectEditorTarget?
    @State private var pendingDelete: Project?

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: ProjectsModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: ProjectsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: "folder",
                title: String(localized: "No projects yet"),
                message: String(localized: "Create a project to organize your links."),
                actionTitle: String(localized: "Create Project"),
                action: { editing = .new }
            ),
            retry: { [list = model.list] in await list.refresh() }
        ) { projects in
            List {
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        Button {
                            editing = .existing(project)
                        } label: {
                            ProjectRow(project: project)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("org.projects.row.\(index)")
                        .accessibilityHint(Text("Edits the name and colour"))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = project } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editing = .existing(project) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        .contextMenu {
                            Button { editing = .existing(project) } label: {
                                Label("Edit…", systemImage: "pencil")
                            }
                            Button(role: .destructive) { pendingDelete = project } label: {
                                Label("Delete…", systemImage: "trash")
                            }
                        }
                    }
                    OrganiseLoadMoreRow(list: model.list)
                } footer: {
                    Text("Group resources into color-coded projects.")
                }
            }
            .refreshable { await model.list.refresh() }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: {
                    Label("Create Project", systemImage: "plus")
                }
                .accessibilityIdentifier("org.projects.create")
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        .onChange(of: app.workspaceScope) { _, _ in Task { await model.list.refresh() } }
        .sheet(item: $editing) { target in
            ProjectEditorSheet(model: model, project: target.project)
        }
        .organiseDeleteFlow(
            $pendingDelete,
            title: String(localized: "Delete this project?"),
            confirmTitle: { String(localized: "Delete \($0.name)") },
            message: String(localized: "Are you sure you want to delete this project? Its links are kept, outside any project. This can't be undone."),
            delete: { [model] project in try await model.delete(project) }
        )
    }
}

/// What the editor sheet opens on.
enum ProjectEditorTarget: Identifiable, Hashable {
    case new
    case existing(Project)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let project): return "project-\(project.id)"
        }
    }

    var project: Project? {
        if case .existing(let project) = self { return project }
        return nil
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            ProjectColorDot(hex: project.color, size: StudioSpace.s4)
                .frame(width: StudioSpace.s6)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: project.name)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(2)
                if let added = organiseAddedLine(project.createdAt) {
                    Text(added)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            Spacer(minLength: StudioSpace.s2)
            Image(systemName: "chevron.right")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, StudioSpace.s1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor

/// Name and colour. The colour comes from the Studio quick picks or the
/// system colour well, and is stored as `#rrggbb`.
struct ProjectEditorSheet: View {
    let model: ProjectsModel
    let project: Project?

    @Environment(\.dismiss) private var dismiss
    @State private var input: ProjectInput
    @State private var error: String?
    @State private var isSaving = false

    init(model: ProjectsModel, project: Project?) {
        self.model = model
        self.project = project
        _input = State(initialValue: project.map(ProjectInput.init) ?? ProjectInput(name: "", color: ProjectPalette.defaultHex))
    }

    private var original: ProjectInput {
        project.map(ProjectInput.init) ?? ProjectInput(name: "", color: ProjectPalette.defaultHex)
    }

    private var trimmedName: String { input.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDirty: Bool { input != original }
    private var canSave: Bool { !trimmedName.isEmpty && isDirty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditorTextField(String(localized: "Name"), text: $input.name,
                                    prompt: String(localized: "Project name"))
                        .onSubmit { Task { await save() } }
                        .accessibilityIdentifier("org.projects.editor.name")
                } footer: {
                    Text("A folder for grouping links, with a colour to find it by.")
                }
                .editorRowBackground()

                Section {
                    swatches
                    ColorPicker(selection: QRHexColor.binding($input.color, fallback: Color.studioAccent),
                                supportsOpacity: false) {
                        HStack(spacing: StudioSpace.s2) {
                            Text("Custom colour")
                            Spacer(minLength: StudioSpace.s2)
                            Text(verbatim: input.color.uppercased())
                                .studioText(.mono)
                                .foregroundStyle(Color.studioText3)
                        }
                    }
                    .accessibilityValue(Text(verbatim: input.color.uppercased()))
                } header: {
                    EditorSectionHeader(String(localized: "Colour"))
                }
                .editorRowBackground()

                Section {
                    HStack(spacing: StudioSpace.s3) {
                        ProjectColorDot(hex: input.color, size: StudioSpace.s4)
                        Text(verbatim: trimmedName.isEmpty ? String(localized: "Project name") : trimmedName)
                            .studioText(.ui)
                            .foregroundStyle(trimmedName.isEmpty ? Color.studioText3 : Color.studioText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Preview"))
                    .accessibilityValue(Text(verbatim: trimmedName))
                } header: {
                    EditorSectionHeader(String(localized: "Preview"))
                } footer: {
                    FormErrorText(message: error)
                }
                .editorRowBackground()
            }
            .resourceEditorForm()
            .navigationTitle(project == nil ? String(localized: "Create project") : String(localized: "Edit project"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel(Text("Saving"))
                    } else {
                        Button(project == nil ? String(localized: "Create") : String(localized: "Save")) {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityIdentifier("org.projects.editor.save")
                    }
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
        }
        .organiseSheetFrame()
    }

    private var swatches: some View {
        HStack(spacing: StudioSpace.s3) {
            ForEach(Array(ProjectPalette.presets.enumerated()), id: \.element) { index, hex in
                let selected = hex.caseInsensitiveCompare(input.color) == .orderedSame
                Button {
                    input.color = hex
                } label: {
                    Circle()
                        .fill(QRHexColor.color(hex) ?? Color.studioText3)
                        .frame(width: StudioSpace.s8, height: StudioSpace.s8)
                        .overlay {
                            Circle()
                                .strokeBorder(selected ? Color.studioText : Color.studioBorder, lineWidth: selected ? 3 : 1)
                        }
                        .padding(StudioSpace.s1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Colour \(index + 1)"))
                .accessibilityValue(Text(verbatim: hex.uppercased()))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, StudioSpace.s1)
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        var sending = input
        sending.name = trimmedName
        do {
            _ = try await model.save(sending, editing: project)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Projects") {
    let model = ProjectsModel(client: OrganisePreviewData.client)
    model.seed(OrganisePreviewData.projects)
    return NavigationStack { ProjectsView(model: model) }
        .environment(AppModel.preview())
}

#Preview("Projects, empty") {
    let model = ProjectsModel(client: OrganisePreviewData.client)
    model.seed([])
    return NavigationStack { ProjectsView(model: model) }
        .environment(AppModel.preview())
}

#Preview("Edit project") {
    ProjectEditorSheet(model: ProjectsModel(client: OrganisePreviewData.client),
                       project: OrganisePreviewData.projects[1])
}

#Preview("New project") {
    ProjectEditorSheet(model: ProjectsModel(client: OrganisePreviewData.client), project: nil)
}
#endif
