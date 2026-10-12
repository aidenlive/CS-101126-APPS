import SwiftUI
import StudioKit
import CardsiteKit

/// The workspace switcher at the head of the iPad and Mac sidebar.
///
/// A native menu whose label is the Studio workspace tile. Choosing a
/// workspace scopes every request to it and rebuilds the screens
/// (`AppModel.selectWorkspace`). Creating, renaming and leaving workspaces
/// live on the Workspace screen.
struct WorkspaceSwitcher: View {
    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 32

    var body: some View {
        Menu {
            WorkspaceMenuItems()
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Workspace")
        .accessibilityValue(app.currentWorkspace?.name ?? String(localized: "Loading"))
        .accessibilityHint("Switches whose links, pages and codes you see")
    }

    private var label: some View {
        HStack(spacing: StudioSpace.s3) {
            Text(glyph)
                .studioText(.ui)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioSurface)
                .frame(width: tileSize, height: tileSize)
                .background(
                    RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                        .fill(Color.studioText)
                )

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: name)
                    .studioText(.uiSm)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(2)
                Text(meta)
                    .studioText(.meta)
                    .foregroundStyle(Color.studioText3)
            }

            Spacer(minLength: 0)

            if case .loading = app.workspaces {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .padding(StudioSpace.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                .fill(Color.studioSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
    }

    private var name: String {
        if let workspace = app.currentWorkspace { return workspace.name }
        if case .failed = app.workspaces { return String(localized: "Workspace") }
        return String(localized: "Loading…")
    }

    private var glyph: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "W"
    }

    private var meta: String {
        guard let workspace = app.currentWorkspace else {
            if case .failed = app.workspaces { return String(localized: "Couldn’t load") }
            return " "
        }
        return WorkspaceMenuItems.describe(workspace)
    }
}

/// The switcher's choices, shared by the sidebar menu and More.
struct WorkspaceMenuItems: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.workspaces {
        case .loaded(let workspaces):
            Picker(selection: selection) {
                ForEach(workspaces) { workspace in
                    Label(workspace.name, systemImage: workspace.isPersonal ? "person" : "person.2")
                        .tag(workspace.id)
                }
            } label: {
                Text("Workspace")
            }
            .pickerStyle(.inline)
        case .failed:
            Button {
                Task { await app.loadWorkspaces() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
        case .idle, .loading:
            Text("Loading workspaces…")
        }
    }

    private var selection: Binding<Int> {
        Binding(
            get: { app.currentWorkspace?.id ?? -1 },
            set: { id in Task { await app.selectWorkspace(id) } }
        )
    }

    /// "PERSONAL" or "SHARED · ADMIN" (rendered in the uppercase meta style).
    static func describe(_ workspace: Workspace) -> String {
        if workspace.isPersonal { return String(localized: "Personal") }
        let role: String
        switch workspace.workspaceRole {
        case .owner: role = String(localized: "Owner")
        case .admin: role = String(localized: "Admin")
        case .member: role = String(localized: "Member")
        }
        return String(localized: "Shared · \(role)")
    }
}

/// The switcher as a row at the top of More on iPhone: a native picker.
struct WorkspacePickerRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.workspaces {
        case .loaded(let workspaces):
            Picker(selection: Binding(
                get: { app.currentWorkspace?.id ?? -1 },
                set: { id in Task { await app.selectWorkspace(id) } }
            )) {
                ForEach(workspaces) { workspace in
                    Text(verbatim: workspace.name).tag(workspace.id)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text("Workspace")
                        if let current = app.currentWorkspace {
                            Text(WorkspaceMenuItems.describe(current))
                                .studioText(.meta)
                                .foregroundStyle(Color.studioText3)
                        }
                    }
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
            }
            .pickerStyle(.menu)
        case .failed(let error):
            Button {
                Task { await app.loadWorkspaces() }
            } label: {
                LabeledContent {
                    Text("Try Again")
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: StudioSpace.s1) {
                            Text("Workspace")
                            Text(error.localizedDescription)
                                .studioText(.uiSm)
                                .foregroundStyle(Color.studioText3)
                        }
                    } icon: {
                        Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                    }
                }
            }
        case .idle, .loading:
            LabeledContent {
                ProgressView()
            } label: {
                Label("Workspace", systemImage: "square.stack.3d.up")
            }
            .accessibilityValue("Loading")
        }
    }
}

#if DEBUG
#Preview("Sidebar switcher") {
    WorkspaceSwitcher()
        .padding(StudioSpace.s4)
        .frame(width: 280)
        .background(Color.studioBgEdge)
        .environment(AppModel.preview())
}

#Preview("More row") {
    List {
        Section { WorkspacePickerRow() }
    }
    .environment(AppModel.preview())
}
#endif
