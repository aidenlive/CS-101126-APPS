import SwiftUI
import Combine
import StudioKit
import CardsiteKit

/// The list for one resource kind: vCards, events, payment links, file
/// links, static pages or splash pages.
///
/// A stack-free destination, so it brings no navigation stack of its own:
/// the shell wraps it in one on iPad and Mac and pushes it onto Library's
/// stack on iPhone. Rows push the kind's editor; + opens the create sheet.
///
/// Each row has the name, address and type detail, all-time clicks and the
/// on/off switch. The context menu and swipe actions copy, open, show the
/// card, open statistics, duplicate (vCards, events, payment links: the
/// server can't copy stored files) and delete.
struct ResourceListScreen: View {
    @Environment(AppModel.self) private var app
    let kind: ResourceKind
    @State private var model: ResourceListModel?

    init(kind: ResourceKind) {
        self.kind = kind
        _model = State(initialValue: nil)
    }

    /// Preview seam: a model already holding rows.
    init(model: ResourceListModel) {
        self.kind = model.kind
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let model {
                ResourceListView(model: model)
            } else {
                ListSkeletonView(head: kind.pageHead)
                    .pageHeadNavigationTitle(kind.pluralTitle)
            }
        }
        .task {
            guard model == nil else { return }
            let created = ResourceListModel(kind: kind, client: app.client)
            created.onError = { [app] error in app.handle(error) }
            model = created
        }
    }
}

private struct ResourceListView: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: ResourceListModel

    @State private var isComposing = false
    @State private var opened: ResourceItem? = nil
    @State private var pendingDelete: ResourceItem? = nil
    @State private var statisticsFor: ResourceItem? = nil
    @State private var actionError: ActionError? = nil
    /// The search text the list was last fetched with.
    @State private var fetchedSearch = ""

    struct ActionError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var kind: ResourceKind { model.kind }

    var body: some View {
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: kind.systemImage,
                title: kind.emptyTitle,
                message: kind.emptyMessage,
                actionTitle: kind.createTitle,
                action: { isComposing = true }
            ),
            head: kind.pageHead,
            retry: { [list = model.list] in await list.refresh() }
        ) { _ in
            rows
        }
        .background(Color.studioBg)
        .pageHeadNavigationTitle(kind.pluralTitle)
        .searchable(text: $model.searchText, prompt: Text(kind.searchPrompt))
        .task(id: model.searchText) { [model] in
            // Debounced: the server is asked once typing pauses.
            let text = model.searchText
            guard model.list.state.value != nil, text != fetchedSearch else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            fetchedSearch = text
            await model.list.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isComposing = true
                } label: {
                    Label(kind.createTitle, systemImage: "plus")
                }
                .accessibilityIdentifier("res.\(kind.identifier).create")
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        .task { [options = model.options] in await options.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .resourceCreated)) { note in
            guard note.object as? String == kind.rawValue else { return }
            Task { [list = model.list] in await list.refresh() }
        }
        .navigationDestination(item: $opened) { item in
            ResourceEditorView(kind: kind, item: item, list: model)
        }
        .sheet(isPresented: $isComposing) {
            NavigationStack {
                ResourceEditorView(kind: kind, item: nil, list: model) { created in
                    opened = created
                }
            }
            .cardsiteSheet(.page)
        }
        .sheet(item: $statisticsFor) { item in
            NavigationStack {
                StatisticsScreen(linkID: item.id, subtitle: model.displayAddress(for: item, addresses: app.addresses))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { statisticsFor = nil } label: {
                                EditorBarLabel(title: String(localized: "Close"), systemImage: "xmark")
                            }
                            .keyboardShortcut(.cancelAction)
                        }
                    }
            }
            .cardsiteSheet(.page)
        }
        .confirmationDialog(
            kind.deleteConfirmation,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                Task { await delete(item) }
            }
        } message: { _ in
            Text(kind.deleteConsequence)
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

    private var rows: some View {
        List {
            ListPageHead(kind.pageHead)
            if let error = model.list.refreshError {
                RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                    .studioClearRow()
            }
            if model.visibleItems.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .studioClearRow()
            }
            Section {
                ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        ResourceEditorView(kind: kind, item: item, list: model)
                    } label: {
                        ResourceRow(
                            kind: kind,
                            item: item,
                            address: model.displayAddress(for: item, addresses: app.addresses),
                            isToggling: model.togglingIDs.contains(item.id),
                            setEnabled: { isEnabled in Task { await setEnabled(item, isEnabled) } }
                        )
                    }
                    .accessibilityIdentifier("res.\(kind.identifier).row.\(index)")
                    .contextMenu { ResourceMenuItems(actions: actions(for: item)) }
                    .resourceSwipeActions(actions(for: item))
                }
                .studioRowBackground()
            }
            if model.list.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .studioClearRow()
                .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
            }
        }
        .studioList()
        .refreshable { [list = model.list] in await list.refresh() }
    }

    private func actions(for item: ResourceItem) -> ResourceActionSet {
        ResourceActionSet(
            url: model.publicURL(for: item, addresses: app.addresses),
            cardURL: item.slug.flatMap { app.addresses.cardURL(for: $0) },
            isEnabled: kind.hasAddress ? item.isEnabled : nil,
            statistics: kind.hasAddress ? { statisticsFor = item } : nil,
            duplicate: kind.supportsDuplicate ? { Task { await duplicate(item) } } : nil,
            setEnabled: kind.hasAddress ? { isEnabled in Task { await setEnabled(item, isEnabled) } } : nil,
            delete: { pendingDelete = item }
        )
    }

    private func setEnabled(_ item: ResourceItem, _ isEnabled: Bool) async {
        do {
            try await model.setEnabled(item, isEnabled)
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t change the status"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func duplicate(_ item: ResourceItem) async {
        do {
            let copy = try await model.duplicate(item)
            Haptics.success()
            opened = copy
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t duplicate"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func delete(_ item: ResourceItem) async {
        do {
            try await model.delete(item)
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t delete"),
                                      message: error.asAPIError.localizedDescription)
        }
        pendingDelete = nil
    }
}

extension ResourceKind {
    /// The list's page head, in every state of the list.
    var pageHead: ListPageHeadContent {
        ListPageHeadContent(kicker: kicker, title: pluralTitle, description: blurb)
    }
}

/// A resource in the shared row anatomy: the name with its state, the
/// address and the type's detail underneath, clicks and the Live switch
/// trailing.
struct ResourceRow: View {
    let kind: ResourceKind
    let item: ResourceItem
    let address: String?
    var isToggling = false
    var setEnabled: (@MainActor (Bool) -> Void)?

    var body: some View {
        CardsiteResourceRow(
            systemImage: kind.systemImage,
            isLive: item.isEnabled,
            title: Text(verbatim: item.name),
            subtitle: address.map { Text(verbatim: $0) },
            detail: item.detail.isEmpty ? nil : Text(verbatim: item.detail),
            state: kind.hasAddress
                ? ResourceState(isEnabled: item.isEnabled, isLapsing: item.isLapsing)
                : (item.isLapsing ? .lapsing : nil),
            clicks: item.clicks
        ) {
            if kind.hasAddress, let setEnabled {
                LiveSwitch(isOn: item.isEnabled, isBusy: isToggling, set: setEnabled)
            }
        }
    }
}

#Preview("vCards") {
    let app = AppModel(configuration: .preview)
    let model = ResourceListModel(kind: .vcard, client: app.client)
    model.list.insert(.link(.previewVCard))
    return NavigationStack {
        ResourceListScreen(model: model)
    }
    .environment(app)
}

#Preview("Empty splash pages") {
    let app = AppModel(configuration: .preview)
    let model = ResourceListModel(kind: .splash, client: app.client)
    NavigationStack {
        ResourceListScreen(model: model)
    }
    .environment(app)
}

#Preview("Rows") {
    List {
        ResourceRow(kind: .vcard, item: .link(.previewVCard), address: "card.site/ada", setEnabled: { _ in })
        ResourceRow(kind: .event, item: .link(.previewEvent), address: "card.site/launch-night", setEnabled: { _ in })
        ResourceRow(kind: .paymentLink, item: .link(.previewPaymentLink), address: "card.site/tip-jar", setEnabled: { _ in })
        ResourceRow(kind: .file, item: .link(.previewFile), address: "card.site/brochure", setEnabled: { _ in })
        ResourceRow(kind: .splash, item: .splash(.preview), address: nil)
    }
}
