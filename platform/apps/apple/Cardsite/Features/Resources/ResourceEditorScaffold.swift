import SwiftUI
import StudioKit
import CardsiteKit

/*
 ResourceEditorScaffold — the one frame every resource editor sits in, so
 a vCard, an event, a payment link, a file link, a static page and a splash
 page look and behave the same:

   · a saved resource gets the header (status, name, address, Copy / Open /
     Card View plus the type's own actions, the on/off switch, clicks and
     statistics), Save in the toolbar through `.unsavedChanges`, pull to
     refresh, and the danger zone;
   · a new one gets Cancel and Create, asks before throwing a draft away,
     and blocks swipe-to-dismiss while it has one.

     ResourceEditorScaffold(kind: .vcard, model: model, list: list) { item in
         // extra header actions for the saved resource
     } fields: {
         // the type's Form sections
     }

 The type's own sections come from the shared ResourceEditor pieces
 (AddressField, GatingSection, EditorTextField…).
 */
struct ResourceEditorScaffold<Model: ResourceEditorState, Actions: View, Fields: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let kind: ResourceKind
    let model: Model
    let list: ResourceListModel
    var onCreated: (ResourceItem) -> Void
    var onDeleted: () -> Void
    private let actions: (ResourceItem) -> Actions
    private let fields: () -> Fields
    /// Fixed when the editor opens: a create sheet closes once it has created.
    private let isNew: Bool

    @State private var isConfirmingDelete = false
    @State private var isConfirmingCancel = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showsStatistics = false
    @State private var copied = false
    @State private var toggleError: String?

    init(kind: ResourceKind, model: Model, list: ResourceListModel,
         onCreated: @escaping (ResourceItem) -> Void = { _ in },
         onDeleted: @escaping () -> Void = {},
         @ViewBuilder actions: @escaping (ResourceItem) -> Actions,
         @ViewBuilder fields: @escaping () -> Fields) {
        self.kind = kind
        self.model = model
        self.list = list
        self.onCreated = onCreated
        self.onDeleted = onDeleted
        self.actions = actions
        self.fields = fields
        self.isNew = model.item == nil
    }

    var body: some View {
        Group {
            if isNew {
                form.modifier(CreateChrome(kind: kind, model: model, isConfirmingCancel: $isConfirmingCancel,
                                           onCreated: onCreated))
            } else {
                form
                    .unsavedChanges(
                        isDirty: model.isDirty,
                        isSaving: model.isSaving,
                        save: { [model] in await model.save() },
                        discard: { [model] in model.discard() }
                    )
                    .refreshable { [model, list] in
                        async let item: Void = model.refresh()
                        async let options: Void = list.options.load()
                        _ = await (item, options)
                    }
                    .task { [model] in await model.refresh() }
            }
        }
        .navigationTitle(isNew ? kind.createTitle : kind.editTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !isNew, let url = currentItem.flatMap({ list.publicURL(for: $0, addresses: app.addresses) }) {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { [options = list.options] in await options.loadIfNeeded() }
        .confirmationDialog(kind.deleteConfirmation, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text(kind.deleteConsequence)
        }
        .alert("Couldn’t delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(isPresented: $showsStatistics) {
            if let item = currentItem {
                NavigationStack {
                    StatisticsScreen(linkID: item.id, subtitle: list.displayAddress(for: item, addresses: app.addresses))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsStatistics = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 560)
                #endif
            }
        }
    }

    /// The saved resource as the list has it now (the switch acts on the list).
    private var currentItem: ResourceItem? {
        model.item.map(list.current)
    }

    private var form: some View {
        Form {
            if let item = currentItem {
                header(item)
            }
            if let error = model.refreshError {
                Section {
                    RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                }
                .listRowBackground(Color.clear)
            }
            fields()
            if let message = model.formError {
                Section {
                    FormErrorText(message: message)
                }
                .editorRowBackground()
            }
            if let item = currentItem {
                dangerZone(item)
            }
        }
        .resourceEditorForm()
    }

    // MARK: Header

    private func header(_ item: ResourceItem) -> some View {
        Section {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                HStack(spacing: StudioSpace.s2) {
                    statusPill(item)
                    if model.didJustSave {
                        StudioStatusPill(String(localized: "Saved"), tone: .success)
                            .transition(.opacity)
                    }
                }
                Text(verbatim: item.name)
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let address = list.displayAddress(for: item, addresses: app.addresses) {
                    Text(verbatim: address)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s2) { headerActions(item) }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) { headerActions(item) }
                }
                .padding(.top, StudioSpace.s1)
            }
            .padding(.vertical, StudioSpace.s2)

            if kind.hasAddress {
                Toggle(isOn: Binding(
                    get: { item.isEnabled },
                    set: { newValue in Task { await setEnabled(item, newValue) } }
                )) {
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        item.isEnabled ? Text("Active") : Text("Disabled")
                        Text(item.isEnabled
                             ? String(localized: "Resolving")
                             : String(localized: "Returns 404. The address stays yours."))
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                .toggleStyle(.switch)
                .disabled(list.togglingIDs.contains(item.id))
                if let toggleError {
                    FormErrorText(message: toggleError)
                }

                if let clicks = item.clicks {
                    LabeledContent {
                        Text(verbatim: clicks.grouped)
                            .studioText(.titleSm)
                            .foregroundStyle(Color.studioText)
                            .monospacedDigit()
                    } label: {
                        Text("Clicks, all time")
                    }
                }
                Button {
                    showsStatistics = true
                } label: {
                    Label("Full statistics", systemImage: "chart.bar.xaxis")
                }
            }

            if item.isLapsing {
                StudioBanner(
                    lead: String(localized: "This address is in its release window."),
                    message: String(localized: "It may be released to others soon. How addresses are kept: cardsite.com/url-lifecycle."),
                    tone: .warning
                )
            }
        }
        .editorRowBackground()
    }

    @ViewBuilder
    private func statusPill(_ item: ResourceItem) -> some View {
        if !kind.hasAddress {
            StudioStatusPill(kind.title, tone: .neutral)
        } else if !item.isEnabled {
            StudioStatusPill(String(localized: "Off"), tone: .neutral)
        } else if item.isLapsing {
            StudioStatusPill(String(localized: "Lapsing"), tone: .warning)
        } else {
            StudioStatusPill(String(localized: "Live"), tone: .success)
        }
    }

    @ViewBuilder
    private func headerActions(_ item: ResourceItem) -> some View {
        if let url = list.publicURL(for: item, addresses: app.addresses) {
            StudioButton(copied ? String(localized: "Copied") : String(localized: "Copy"),
                         systemImage: copied ? "checkmark" : "doc.on.doc",
                         variant: .primary) {
                copy(url)
            }
            Link(destination: url) {
                Label("Open", systemImage: "safari")
            }
            .buttonStyle(.bordered)
        }
        if let slug = item.slug, let card = app.addresses.cardURL(for: slug) {
            Link(destination: card) {
                Label("Card View", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            .buttonStyle(.bordered)
        }
        actions(item)
    }

    private func copy(_ url: URL) {
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func setEnabled(_ item: ResourceItem, _ isEnabled: Bool) async {
        toggleError = nil
        do {
            try await list.setEnabled(item, isEnabled)
        } catch {
            toggleError = error.asAPIError.localizedDescription
        }
    }

    // MARK: Danger zone

    private func dangerZone(_ item: ResourceItem) -> some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                HStack {
                    Label(String(localized: "Delete \(kind.title)"), systemImage: "trash")
                    Spacer()
                    if isDeleting { ProgressView() }
                }
            }
            .disabled(isDeleting)
        } header: {
            EditorSectionHeader(String(localized: "Danger zone"))
        } footer: {
            Text(kind.deleteConsequence)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .editorRowBackground()
    }

    private func delete() async {
        guard let item = currentItem else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await list.delete(item)
            model.discard()
            onDeleted()
            dismiss()
        } catch {
            deleteError = error.asAPIError.localizedDescription
        }
    }
}

/// Cancel and Create for a new resource, in a sheet.
private struct CreateChrome<Model: ResourceEditorState>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let kind: ResourceKind
    let model: Model
    @Binding var isConfirmingCancel: Bool
    let onCreated: (ResourceItem) -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.isDirty { isConfirmingCancel = true } else { dismiss() }
                    }
                    .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                            .accessibilityLabel(Text("Saving"))
                    } else {
                        Button("Create") { Task { await create() } }
                            .keyboardShortcut("s", modifiers: .command)
                            .accessibilityIdentifier("res.editor.save")
                    }
                }
            }
            .interactiveDismissDisabled(model.isDirty || model.isSaving)
            .confirmationDialog("Discard this draft?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("The \(kind.title) hasn’t been created yet.")
            }
    }

    private func create() async {
        guard await model.save(), let item = model.item else { return }
        onCreated(item)
        dismiss()
    }
}
