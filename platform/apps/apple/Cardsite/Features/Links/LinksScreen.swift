import SwiftUI
import StudioKit
import CardsiteKit

/// Short links: list and detail. Splits into two columns on iPad and Mac,
/// collapses to a stack on iPhone.
///
/// Each row has the address, destination, all-time clicks and an on/off
/// switch. The context menu and swipe actions copy, open, show the card,
/// open statistics, duplicate and delete. Picking another link while the
/// open one has unsaved changes asks first.
struct LinksScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LinksModel.self) private var model
    @State private var selection: Resource.ID? = nil
    /// The search text the list was last fetched with.
    @State private var fetchedSearch = ""
    @State private var isComposing = false
    @State private var pendingDelete: Resource? = nil
    @State private var statisticsFor: Resource? = nil
    @State private var actionError: ActionError? = nil
    @State private var unsaved = UnsavedChangesTracker()

    struct ActionError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        @Bindable var bindable = model
        NavigationSplitView {
            ListStateView(
                state: model.list.state,
                empty: .init(
                    systemImage: "link",
                    title: String(localized: "No short links yet"),
                    message: String(localized: "Shorten your first URL to start tracking clicks, locations, and referrers."),
                    actionTitle: String(localized: "New Short Link"),
                    action: { isComposing = true }
                ),
                retry: { [list = model.list] in await list.refresh() }
            ) { _ in
                linkList
            }
            .navigationTitle("Links")
            .searchable(text: $bindable.searchText, prompt: Text("Search addresses and destinations"))
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
                        Label("New Short Link", systemImage: "plus")
                    }
                    .accessibilityIdentifier("links.create")
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            #endif
        } detail: {
            NavigationStack {
                if let id = selection, let link = model.list.items.first(where: { $0.id == id }) {
                    LinkDetailView(link: link) { selection = nil }
                        .id(link.id)
                } else {
                    SplitPlaceholder(systemImage: "link",
                                     title: String(localized: "Select a link"),
                                     message: String(localized: "Its address, destination, settings and traffic appear here."))
                }
            }
        }
        .environment(unsaved)
        .unsavedSelectionAlert(unsaved)
        .task { [list = model.list] in await list.loadIfNeeded() }
        .sheet(isPresented: $isComposing) {
            LinkEditorView { link in unsaved.guarding($selection).wrappedValue = link.id }
        }
        .sheet(item: $statisticsFor) { link in
            NavigationStack {
                StatisticsScreen(linkID: link.id, subtitle: app.addresses.display(for: link.slug))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { statisticsFor = nil }
                        }
                    }
            }
            .cardsiteSheet(.page)
        }
        .confirmationDialog(
            ResourceKind.shortLinkDeleteConfirmation,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { link in
            Button("Delete", role: .destructive) {
                Task { await delete(link) }
            }
        } message: { _ in
            Text(ResourceKind.shortLinkDeleteConsequence)
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

    private var linkList: some View {
        List(selection: unsaved.guarding($selection)) {
            if let error = model.list.refreshError {
                RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                    .studioClearRow()
            }
            if model.visibleLinks.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .studioClearRow()
            }
            ForEach(model.visibleLinks) { link in
                NavigationLink(value: link.id) {
                    LinkRow(
                        link: link,
                        isToggling: model.togglingIDs.contains(link.id),
                        setEnabled: { isEnabled in Task { await setEnabled(link, isEnabled) } }
                    )
                }
                .accessibilityIdentifier("links.row.\(link.id)")
                .contextMenu { ResourceMenuItems(actions: actions(for: link)) }
                .resourceSwipeActions(actions(for: link))
                .studioRowBackground(isSelected: selection == link.id)
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

    private func actions(for link: Resource) -> ResourceActionSet {
        ResourceActionSet(
            url: app.addresses.url(for: link.slug),
            cardURL: app.addresses.cardURL(for: link.slug),
            isEnabled: link.isEnabled,
            statistics: { statisticsFor = link },
            duplicate: { Task { await duplicate(link) } },
            setEnabled: { isEnabled in Task { await setEnabled(link, isEnabled) } },
            delete: { pendingDelete = link }
        )
    }

    private func setEnabled(_ link: Resource, _ isEnabled: Bool) async {
        do {
            try await model.setEnabled(link, isEnabled)
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t change the status"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func duplicate(_ link: Resource) async {
        do {
            let copy = try await model.duplicate(link)
            Haptics.success()
            unsaved.guarding($selection).wrappedValue = copy.id
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t duplicate"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func delete(_ link: Resource) async {
        do {
            try await model.delete(link)
            if selection == link.id { selection = nil }
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t delete"),
                                      message: error.asAPIError.localizedDescription)
        }
        pendingDelete = nil
    }
}

/// A short link in the shared row anatomy: the address with its state,
/// the destination and clicks underneath, the Live switch trailing.
struct LinkRow: View {
    @Environment(AppModel.self) private var app
    let link: Resource
    var isToggling = false
    var setEnabled: (@MainActor (Bool) -> Void)?

    var body: some View {
        CardsiteResourceRow(
            systemImage: "link",
            isLive: link.isEnabled,
            title: Text(verbatim: app.addresses.display(for: link.slug)),
            subtitle: Text(verbatim: link.destinationHost),
            state: ResourceState(isEnabled: link.isEnabled, isLapsing: link.isLapsing),
            clicks: link.clicks
        ) {
            if let setEnabled {
                LiveSwitch(isOn: link.isEnabled, isBusy: isToggling, set: setEnabled)
            }
        }
    }
}

extension Resource {
    /// "example.com/menu" for display; the full destination stays one tap away.
    var destinationHost: String {
        guard let destination, let url = URL(string: destination), let host = url.host() else {
            return destination ?? String(localized: "No destination")
        }
        let path = url.path()
        let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return path.isEmpty || path == "/" ? trimmedHost : trimmedHost + path
    }
}

#Preview("Links") {
    let app = AppModel(configuration: .preview)
    let links = LinksModel(client: app.client)
    LinksScreen()
        .environment(app)
        .environment(links)
}

#Preview("Row") {
    List {
        LinkRow(link: Resource(id: 1, slug: "spring-menu", destination: "https://example.com/menu", clicks: 1_284),
                setEnabled: { _ in })
        LinkRow(link: Resource(id: 2, slug: "launch", destination: "https://www.example.com/", clicks: 0, isEnabled: false),
                setEnabled: { _ in })
    }
    .environment(AppModel(configuration: .preview))
}
