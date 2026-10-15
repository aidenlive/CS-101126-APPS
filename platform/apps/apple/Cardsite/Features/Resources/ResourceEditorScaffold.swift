import SwiftUI
import StudioKit
import CardsiteKit

/*
 ResourceEditorScaffold — the one frame every resource editor sits in, so
 a vCard, an event, a payment link, a file link, a static page and a splash
 page look and behave the same:

   · a saved resource gets the shared hero (`ResourceHeaderSection`:
     status, name, address, where it leads, 30-day and all-time figures,
     Copy Link / Open / Card plus the type's own button, the Live switch
     and Statistics); the bar title `/slug` with the host under it; one …
     menu (Share, Show Card, Statistics, Duplicate, the type's extras,
     Delete); ✓ only with changes through `.unsavedChanges`; pull to
     refresh; and the danger zone;
   · a new one gets ✕ and ✓ Create, asks before throwing a draft away,
     and blocks swipe-to-dismiss while it has one.

     ResourceEditorScaffold(kind: .vcard, model: model, list: list) { item in
         // the type's own hero button (a Label, so it can drop to a symbol)
     } menu: { item in
         // the type's extra … menu items
     } fields: {
         // the type's Form sections, the live preview first
     }

 The type's own sections come from the shared ResourceEditor pieces
 (AddressField, GatingSection, EditorTextField…).
 */
struct ResourceEditorScaffold<Model: ResourceEditorState, Actions: View, MenuItems: View, Fields: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.toasts) private var toasts

    let kind: ResourceKind
    let model: Model
    let list: ResourceListModel
    var onCreated: (ResourceItem) -> Void
    var onDeleted: () -> Void
    private let actions: (ResourceItem) -> Actions
    private let menuItems: (ResourceItem) -> MenuItems
    private let fields: () -> Fields
    /// Fixed when the editor opens: a create sheet closes once it has created.
    private let isNew: Bool

    @State private var isConfirmingDelete = false
    @State private var isConfirmingCancel = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    @State private var showsStatistics = false
    @State private var toggleError: String? = nil
    @State private var isDuplicating = false
    @State private var duplicateError: String? = nil
    /// Pageviews and visitors over the last 30 days, for the hero.
    @State private var recent: (pageviews: Int, visitors: Int)? = nil

    init(kind: ResourceKind, model: Model, list: ResourceListModel,
         onCreated: @escaping (ResourceItem) -> Void = { _ in },
         onDeleted: @escaping () -> Void = {},
         @ViewBuilder actions: @escaping (ResourceItem) -> Actions,
         @ViewBuilder menu: @escaping (ResourceItem) -> MenuItems,
         @ViewBuilder fields: @escaping () -> Fields) {
        self.kind = kind
        self.model = model
        self.list = list
        self.onCreated = onCreated
        self.onDeleted = onDeleted
        self.actions = actions
        self.menuItems = menu
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
                    .task(id: model.item?.id) { await loadRecentTraffic() }
                    .editorMoreMenu { moreMenu }
            }
        }
        .navigationTitle(Text(verbatim: barTitle))
        .editorSubtitle(barSubtitle)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        .alert(String(localized: "Couldn’t duplicate"), isPresented: Binding(get: { duplicateError != nil }, set: { if !$0 { duplicateError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateError ?? "")
        }
        .sheet(isPresented: $showsStatistics) {
            if let item = currentItem {
                NavigationStack {
                    StatisticsScreen(linkID: item.id, subtitle: list.displayAddress(for: item, addresses: app.addresses))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showsStatistics = false } label: {
                                    EditorBarLabel(title: String(localized: "Close"), systemImage: "xmark")
                                }
                                .keyboardShortcut(.cancelAction)
                            }
                        }
                }
                .cardsiteSheet(.page)
            }
        }
    }

    // MARK: Bar

    /// "/slug" for anything with an address, else the type ("New vCard",
    /// "Splash page").
    private var barTitle: String {
        if isNew { return kind.createTitle }
        if let slug = currentItem?.slug, !slug.isEmpty { return "/" + slug }
        return currentItem?.name ?? kind.editTitle
    }

    /// The host under the title, or the type when there is no address.
    private var barSubtitle: String? {
        guard !isNew, let item = currentItem else { return nil }
        if let url = list.publicURL(for: item, addresses: app.addresses), let host = url.host() {
            return host
        }
        return kind.title
    }

    /// Share and card; statistics and duplicate; the type's extras; delete.
    @ViewBuilder
    private var moreMenu: some View {
        if let item = currentItem {
            if let url = list.publicURL(for: item, addresses: app.addresses) {
                ShareLink(item: url) { ResourceVerb.share.label }
            }
            if let card = item.slug.flatMap({ app.addresses.cardURL(for: $0) }) {
                Button { openURL(card) } label: { ResourceVerb.showCard.label }
            }
            Divider()
            if kind.hasAddress {
                Button { showsStatistics = true } label: { ResourceVerb.statistics.label }
            }
            if kind.supportsDuplicate {
                Button { Task { await duplicate(item) } } label: { ResourceVerb.duplicate.label }
                    .disabled(isDuplicating)
            }
            menuItems(item)
            Divider()
            Button(role: .destructive) { isConfirmingDelete = true } label: { ResourceVerb.delete.label }
                .disabled(isDeleting)
        }
    }

    private func duplicate(_ item: ResourceItem) async {
        guard !isDuplicating else { return }
        isDuplicating = true
        defer { isDuplicating = false }
        do {
            let copy = try await list.duplicate(item)
            Haptics.success()
            toasts?.show(copy.slug.map { String(localized: "Duplicated as /\($0). The copy starts switched off.") }
                         ?? String(localized: "Duplicated."), variant: .success)
        } catch {
            duplicateError = error.asAPIError.localizedDescription
        }
    }

    private func loadRecentTraffic() async {
        guard kind.hasAddress, let id = model.item?.id else { return }
        let end = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end
        do {
            let days = try await list.client.trafficOverview(.link(id), from: start, to: end)
            recent = (days.reduce(0) { $0 + $1.pageviews }, days.reduce(0) { $0 + $1.visitors })
        } catch {
            // The hero shows "—"; Statistics has the full story.
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
            subtitle: kind == .paymentLink ? ResourceItem.host(of: item.link?.destination) : nil,
            url: list.publicURL(for: item, addresses: app.addresses),
            cardURL: item.slug.flatMap { app.addresses.cardURL(for: $0) },
            toggle: kind.hasAddress
                ? ResourceLiveToggle(isOn: item.isEnabled,
                        isBusy: list.togglingIDs.contains(item.id),
                        error: toggleError,
                        set: { isOn in Task { await setEnabled(item, isOn) } })
                : nil,
            figures: kind.hasAddress
                ? [
                    ResourceFigure(title: String(localized: "Clicks · 30d"), value: recent?.pageviews),
                    ResourceFigure(title: String(localized: "Visitors · 30d"), value: recent?.visitors),
                    ResourceFigure(title: String(localized: "All time"), value: item.clicks),
                ]
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

extension ResourceEditorScaffold where MenuItems == EmptyView {
    /// A type with no … menu items of its own.
    init(kind: ResourceKind, model: Model, list: ResourceListModel,
         onCreated: @escaping (ResourceItem) -> Void = { _ in },
         onDeleted: @escaping () -> Void = {},
         @ViewBuilder actions: @escaping (ResourceItem) -> Actions,
         @ViewBuilder fields: @escaping () -> Fields) {
        self.init(kind: kind, model: model, list: list, onCreated: onCreated, onDeleted: onDeleted,
                  actions: actions, menu: { _ in EmptyView() }, fields: fields)
    }
}

/// ✕ and ✓ Create for a new resource, in a sheet.
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
                    Button {
                        if model.isDirty { isConfirmingCancel = true } else { dismiss() }
                    } label: {
                        EditorBarLabel.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                            .accessibilityLabel(Text("Creating"))
                    } else {
                        Button { Task { await create() } } label: { EditorBarLabel.create() }
                            .keyboardShortcut("s", modifiers: .command)
                            .tint(Color.studioAccentLine)
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
