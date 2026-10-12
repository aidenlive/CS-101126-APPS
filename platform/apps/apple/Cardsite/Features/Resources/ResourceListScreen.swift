import SwiftUI
import Combine
import StudioKit
import CardsiteKit

/// The list for one resource kind: vCards, events, payment links, file
/// links, static pages or splash pages.
///
/// A `.more` destination, so it brings no navigation stack of its own: the
/// shell wraps it in one on iPad and Mac and pushes it onto More's stack on
/// iPhone. Rows push the kind's editor; + opens the create sheet.
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
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.studioBg)
                    .accessibilityLabel(Text("Loading"))
                    .navigationTitle(kind.pluralTitle)
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
            retry: { [list = model.list] in await list.refresh() }
        ) { _ in
            rows
        }
        .background(Color.studioBg)
        .navigationTitle(kind.pluralTitle)
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
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
        }
        .sheet(item: $statisticsFor) { item in
            NavigationStack {
                StatisticsScreen(linkID: item.id, subtitle: model.displayAddress(for: item, addresses: app.addresses))
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
            kind.deleteConfirmation,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button(String(localized: "Delete \(item.name)"), role: .destructive) {
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
            if let error = model.list.refreshError {
                RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if model.visibleItems.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
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
                .listRowBackground(Color.studioSurface)
                .contextMenu { menu(for: item) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDelete = item } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    if kind.supportsDuplicate {
                        Button { Task { await duplicate(item) } } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.studioInfo)
                    }
                    if kind.hasAddress {
                        Button { statisticsFor = item } label: {
                            Label("Statistics", systemImage: "chart.bar.xaxis")
                        }
                        .tint(.studioAccentLine)
                    }
                }
                .swipeActions(edge: .leading) {
                    if let url = model.publicURL(for: item, addresses: app.addresses) {
                        Button {
                            copy(url)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .tint(.studioInfo)
                    }
                }
            }
            if model.list.hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.studioBg)
        .refreshable { [list = model.list] in await list.refresh() }
    }

    @ViewBuilder
    private func menu(for item: ResourceItem) -> some View {
        if let url = model.publicURL(for: item, addresses: app.addresses) {
            Button {
                copy(url)
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
        if let slug = item.slug, let card = app.addresses.cardURL(for: slug) {
            Link(destination: card) {
                Label("Card View", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
        }
        if kind.hasAddress {
            Divider()
            Button {
                statisticsFor = item
            } label: {
                Label("View statistics", systemImage: "chart.bar.xaxis")
            }
        }
        if kind.supportsDuplicate {
            Button {
                Task { await duplicate(item) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        if kind.hasAddress {
            Button {
                Task { await setEnabled(item, !item.isEnabled) }
            } label: {
                item.isEnabled
                    ? Label("Disable", systemImage: "pause.circle")
                    : Label("Enable", systemImage: "play.circle")
            }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = item } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    private func copy(_ url: URL) {
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
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

/// Row anatomy, as the links list: leading glyph, the name with its
/// status, the address and the type's detail underneath, clicks and the
/// on/off switch trailing.
struct ResourceRow: View {
    let kind: ResourceKind
    let item: ResourceItem
    let address: String?
    var isToggling = false
    var setEnabled: (@MainActor (Bool) -> Void)?

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: kind.systemImage)
                .imageScale(.medium)
                .foregroundStyle(item.isEnabled ? Color.studioAccentLine : Color.studioText3)
                .frame(width: StudioSpace.s8, height: StudioSpace.s8)
                .background(Color.studioSurface2, in: RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                HStack(spacing: StudioSpace.s2) {
                    Text(verbatim: item.name)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(2)
                    if kind.hasAddress, !item.isEnabled {
                        StudioStatusPill(String(localized: "Off"), tone: .neutral)
                    } else if item.isLapsing {
                        StudioStatusPill(String(localized: "Lapsing"), tone: .warning)
                    }
                }
                if let address {
                    Text(verbatim: address)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: StudioSpace.s2) {
                    if !item.detail.isEmpty {
                        Text(verbatim: item.detail)
                            .lineLimit(2)
                    }
                    Spacer(minLength: StudioSpace.s2)
                    if let clicks = item.clicks {
                        Label(clicks.grouped, systemImage: "cursorarrow.click")
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                            .accessibilityLabel(Text("\(clicks) clicks"))
                    }
                }
            }
            .studioText(.uiSm)
            .foregroundStyle(Color.studioText3)
            .accessibilityElement(children: .combine)

            if kind.hasAddress, let setEnabled {
                Toggle(isOn: Binding(get: { [isOn = item.isEnabled] in isOn }, set: { [setEnabled] in setEnabled($0) })) {
                    Text("Active")
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.studioAccent)
                .disabled(isToggling)
                .accessibilityLabel(Text("Active"))
                .accessibilityValue(item.isEnabled ? Text("On") : Text("Off"))
            }
        }
        .padding(.vertical, StudioSpace.s1)
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
