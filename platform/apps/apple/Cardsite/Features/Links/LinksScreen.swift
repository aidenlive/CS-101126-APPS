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
    @Environment(\.openURL) private var openURL
    @State private var selection: Resource.ID?
    /// The search text the list was last fetched with.
    @State private var fetchedSearch = ""
    @State private var isComposing = false
    @State private var pendingDelete: Resource?
    @State private var statisticsFor: Resource?
    @State private var actionError: ActionError?
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
                    ContentUnavailableView("Select a link", systemImage: "link",
                                           description: Text("Its address, destination, settings and traffic appear here."))
                        .background(Color.studioBg)
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
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 560)
            #endif
        }
        .confirmationDialog(
            "Delete this link?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { link in
            Button("Delete \(app.addresses.display(for: link.slug))", role: .destructive) {
                Task { await delete(link) }
            }
        } message: { _ in
            Text("Anyone who opens or scans this address will get a not-found page. This can't be undone.")
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
                    .listRowSeparator(.hidden)
            }
            if model.visibleLinks.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .listRowSeparator(.hidden)
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
                .contextMenu { menu(for: link) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDelete = link } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { Task { await duplicate(link) } } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.studioInfo)
                    Button { statisticsFor = link } label: {
                        Label("Statistics", systemImage: "chart.bar.xaxis")
                    }
                    .tint(.studioAccentLine)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        copy(link)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .tint(.studioInfo)
                    if let url = app.addresses.url(for: link.slug) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open", systemImage: "safari")
                        }
                        .tint(.studioText2)
                    }
                }
            }
            if model.list.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
            }
        }
        .refreshable { await model.list.refresh() }
    }

    @ViewBuilder
    private func menu(for link: Resource) -> some View {
        if let url = app.addresses.url(for: link.slug) {
            Button {
                copy(link)
            } label: {
                Label("Copy public URL", systemImage: "doc.on.doc")
            }
            Link(destination: url) {
                Label("Open public link", systemImage: "safari")
            }
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        if let card = app.addresses.cardURL(for: link.slug) {
            Link(destination: card) {
                Label("Card View", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
        }
        Divider()
        Button {
            statisticsFor = link
        } label: {
            Label("View statistics", systemImage: "chart.bar.xaxis")
        }
        Button {
            Task { await duplicate(link) }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            Task { await setEnabled(link, !link.isEnabled) }
        } label: {
            link.isEnabled
                ? Label("Disable link", systemImage: "pause.circle")
                : Label("Enable link", systemImage: "play.circle")
        }
        Divider()
        Button(role: .destructive) { pendingDelete = link } label: {
            Label("Delete link…", systemImage: "trash")
        }
    }

    private func copy(_ link: Resource) {
        guard let url = app.addresses.url(for: link.slug) else { return }
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
    }

    private func setEnabled(_ link: Resource, _ isEnabled: Bool) async {
        do {
            try await model.setEnabled(link, isEnabled)
        } catch {
            actionError = ActionError(title: String(localized: "Failed to update link status"),
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

/// Row anatomy: leading glyph, address with its status, destination and
/// clicks underneath, and the on/off switch trailing.
struct LinkRow: View {
    @Environment(AppModel.self) private var app
    let link: Resource
    var isToggling = false
    var setEnabled: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            RowGlyphTile(systemImage: "link", isActive: link.isEnabled)

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                HStack(spacing: StudioSpace.s2) {
                    Text(app.addresses.display(for: link.slug))
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !link.isEnabled {
                        StudioStatusPill(String(localized: "Off"), tone: .neutral)
                    } else if link.isLapsing {
                        StudioStatusPill(String(localized: "Lapsing"), tone: .warning)
                    }
                }
                HStack(spacing: StudioSpace.s2) {
                    Text(link.destinationHost)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: StudioSpace.s2)
                    Label(link.clicks.grouped, systemImage: "cursorarrow.click")
                        .labelStyle(.titleAndIcon)
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(link.clicks) clicks"))
                }
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
            }
            .accessibilityElement(children: .combine)

            if let setEnabled {
                Toggle(isOn: Binding(get: { link.isEnabled }, set: { setEnabled($0) })) {
                    Text("Active")
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.studioAccent)
                .disabled(isToggling)
                .accessibilityLabel(Text("Active"))
                .accessibilityValue(link.isEnabled ? Text("On") : Text("Off"))
            }
        }
        .padding(.vertical, StudioSpace.s1)
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
