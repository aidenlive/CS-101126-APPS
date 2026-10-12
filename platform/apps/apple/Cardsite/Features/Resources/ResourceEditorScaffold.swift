import SwiftUI
import StudioKit
import CardsiteKit

/*
 ResourceEditorScaffold — the one frame every resource editor sits in, so
 a vCard, an event, a payment link, a file link, a static page and a splash
 page look and behave the same:

   · a saved resource gets the shared `ResourceHeaderSection` (status,
     name, address, Copy Link / Open in Browser / Show Card plus the type's
     own actions, the Live switch, clicks and Statistics), Save in the
     toolbar through `.unsavedChanges`, pull to refresh, and the danger zone;
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
    @State private var deleteError: String? = nil
    @State private var showsStatistics = false
    @State private var toggleError: String? = nil

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
                        discard: { [model] in model.discard() },
                        saveIdentifier: "res.editor.save"
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
        #if os(iOS) || os(visionOS)
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
        .alert(String(localized: "Couldn’t delete"), isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
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
                .cardsiteSheet(.page)
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
                .studioClearRow()
            }
            fields()
            if let message = model.formError {
                Section {
                    FormErrorText(message: message)
                }
                .studioRowBackground()
            }
            if let item = currentItem {
                dangerZone(item)
            }
        }
        .resourceEditorForm()
    }

    // MARK: Header

    private func header(_ item: ResourceItem) -> some View {
        ResourceHeaderSection(
            state: kind.hasAddress ? ResourceState(isEnabled: item.isEnabled, isLapsing: item.isLapsing) : nil,
            kindLabel: kind.title,
            didJustSave: model.didJustSave,
            title: item.name,
            address: list.displayAddress(for: item, addresses: app.addresses),
            url: list.publicURL(for: item, addresses: app.addresses),
            cardURL: item.slug.flatMap { app.addresses.cardURL(for: $0) },
            toggle: kind.hasAddress
                ? ResourceLiveToggle(isOn: item.isEnabled,
                        isBusy: list.togglingIDs.contains(item.id),
                        error: toggleError,
                        set: { isOn in Task { await setEnabled(item, isOn) } })
                : nil,
            figures: kind.hasAddress && item.clicks != nil
                ? [ResourceFigure(title: String(localized: "Clicks · all time"), value: item.clicks)]
                : [],
            isLapsing: item.isLapsing
        ) {
            actions(item)
        } rows: {
            if kind.hasAddress {
                Button {
                    showsStatistics = true
                } label: {
                    ResourceVerb.statistics.label
                }
            }
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
                    ResourceVerb.delete.label
                    Spacer()
                    if isDeleting { ProgressView() }
                }
            }
            .disabled(isDeleting)
        } header: {
            EditorSectionHeader(String(localized: "Danger zone"))
        } footer: {
            Text(kind.deleteConsequence)
        }
        .studioRowBackground()
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
