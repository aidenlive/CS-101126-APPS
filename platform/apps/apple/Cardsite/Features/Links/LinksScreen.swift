import SwiftUI
import StudioKit
import CardsiteKit

/// Short links: list and detail. Splits into two columns on iPad and Mac,
/// collapses to a stack on iPhone.
struct LinksScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LinksModel.self) private var model
    @State private var selection: Resource.ID?
    @State private var isComposing = false
    @State private var pendingDelete: Resource?
    @State private var deleteError: String?

    var body: some View {
        @Bindable var bindable = model
        NavigationSplitView {
            ListStateView(
                state: model.list.state,
                empty: .init(
                    systemImage: "link",
                    title: String(localized: "No short links yet"),
                    message: String(localized: "Give any URL a short address on \(app.addresses.publicHost) that you can share, print or put in a QR code."),
                    actionTitle: String(localized: "New Short Link"),
                    action: { isComposing = true }
                ),
                retry: { [list = model.list] in await list.refresh() }
            ) { _ in
                linkList
            }
            .navigationTitle("Links")
            .searchable(text: $bindable.searchText, prompt: Text("Search addresses and destinations"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isComposing = true
                    } label: {
                        Label("New Short Link", systemImage: "plus")
                    }
                }
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            #endif
        } detail: {
            if let id = selection, let link = model.list.items.first(where: { $0.id == id }) {
                LinkDetailView(link: link)
                    .id(link.id)
            } else {
                ContentUnavailableView("Select a link", systemImage: "link",
                                       description: Text("Its address, destination and traffic appear here."))
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        .sheet(isPresented: $isComposing) {
            LinkEditorView { link in selection = link.id }
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
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var linkList: some View {
        List(selection: $selection) {
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
                    LinkRow(link: link)
                }
                .contextMenu { menu(for: link) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingDelete = link } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Pasteboard.copy(app.addresses.url(for: link.slug)?.absoluteString ?? "")
                        Haptics.success()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .tint(.studioInfo)
                }
            }
            if model.list.hasMore, model.searchText.isEmpty {
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
                Pasteboard.copy(url.absoluteString)
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Link(destination: url) {
                Label("Open", systemImage: "safari")
            }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = link } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    private func delete(_ link: Resource) async {
        do {
            try await model.delete(link)
            if selection == link.id { selection = nil }
        } catch {
            deleteError = error.asAPIError.localizedDescription
        }
        pendingDelete = nil
    }
}

struct LinkRow: View {
    @Environment(AppModel.self) private var app
    let link: Resource

    var body: some View {
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
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
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
