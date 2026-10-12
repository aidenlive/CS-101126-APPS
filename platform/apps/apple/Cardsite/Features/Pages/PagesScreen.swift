import SwiftUI
import StudioKit
import CardsiteKit

/// Bio pages and their editor, as one three-column split view: pages, the
/// selected page's blocks, then the selected block's inspector (or the
/// live preview). On iPhone it collapses to a stack: pages → blocks →
/// inspector. Opening a page on iPad and Mac folds the pages column away to
/// give the editor the room; the sidebar button brings it back.
struct PagesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var selection: BioPage.ID?
    @State private var editor: PageEditorModel?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var isCreating = false
    @State private var pendingDelete: BioPage?
    @State private var actionError: String?
    @StateObject private var toasts = StudioToastCenter()

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            PagesListColumn(
                selection: $selection,
                isCreating: $isCreating,
                pendingDelete: $pendingDelete,
                setEnabled: { page, isOn in Task { await setEnabled(page, isOn) } },
                duplicate: { page in Task { await duplicate(page) } }
            )
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            #endif
        } content: {
            if let editor {
                BlockListColumn(editor: editor, isCompact: isCompact)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("page.editor")
                    .id(editor.pageID)
                    #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360)
                    #endif
            } else {
                ContentUnavailableView(
                    "Select a page",
                    systemImage: "person.crop.square",
                    description: Text("Its blocks appear here, ready to edit.")
                )
                .background(Color.studioBg)
            }
        } detail: {
            if let editor {
                EditorDetailColumn(editor: editor, isCompact: isCompact)
                    .id(editor.pageID)
            } else {
                ContentUnavailableView(
                    "No page open",
                    systemImage: "rectangle.and.pencil.and.ellipsis",
                    description: Text("Choose a page, then a block, to edit it here.")
                )
                .background(Color.studioBg)
            }
        }
        .studioToasts(toasts)
        .task { [list = model.list] in await list.loadIfNeeded() }
        .onChange(of: selection) { _, id in open(id) }
        .onChange(of: model.openRequest, initial: true) { _, id in
            guard let id else { return }
            model.openRequest = nil
            selection = id
        }
        .onDisappear {
            if let editor, editor.hasAnyUnsavedChanges {
                Task { await editor.saveAllDrafts() }
            }
        }
        .sheet(isPresented: $isCreating) {
            CreatePageSheet { page in selection = page.id }
        }
        .confirmationDialog(
            "Delete this bio page?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { page in
            Button("Delete \(app.addresses.display(for: page.slug))", role: .destructive) {
                Task { await delete(page) }
            }
        } message: { _ in
            Text("The address stops working and every block on the page is deleted. This can't be undone.")
        }
        .alert(
            "This block changed",
            isPresented: Binding(get: { editor?.conflict != nil }, set: { if !$0 { editor?.conflict = nil } }),
            presenting: editor?.conflict
        ) { _ in
            Button("Reload") {
                Task { await editor?.reloadAfterConflict() }
            }
            Button("Not Now", role: .cancel) { editor?.conflict = nil }
        } message: { conflict in
            if let name = conflict.editorName {
                Text("\(name) changed this block since you opened it. Reload to see their version, then reapply your edit.")
            } else {
                Text("Someone changed this block since you opened it. Reload to see their version, then reapply your edit.")
            }
        }
        .alert("Couldn't do that", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Editor lifecycle

    private func open(_ id: BioPage.ID?) {
        if let previous = editor, previous.pageID != id, previous.hasAnyUnsavedChanges {
            Task { await previous.saveAllDrafts() }
        }
        guard let id else {
            editor = nil
            return
        }
        guard editor?.pageID != id else { return }
        let next = PageEditorModel(pageID: id, pages: model)
        next.onError = app.handle
        next.announce = { [toasts] message, variant in toasts.show(message, variant: variant) }
        editor = next
        if !isCompact {
            withAnimation(StudioAnimation.base) { columns = .doubleColumn }
        }
    }

    // MARK: Page actions

    private func setEnabled(_ page: BioPage, _ isOn: Bool) async {
        do {
            if let editor, editor.pageID == page.id {
                try await editor.savePage(BioPageChanges(isEnabled: isOn))
            } else {
                try await model.setEnabled(page, isOn)
            }
        } catch {
            actionError = error.asAPIError.localizedDescription
        }
    }

    private func duplicate(_ page: BioPage) async {
        do {
            let copy = try await model.duplicate(page)
            Haptics.success()
            toasts.show(
                String(localized: "Copied to \(app.addresses.display(for: copy.slug)). It's off until you turn it on."),
                variant: .success
            )
        } catch {
            actionError = error.asAPIError.localizedDescription
        }
    }

    private func delete(_ page: BioPage) async {
        do {
            try await model.delete(page)
            if selection == page.id { selection = nil }
        } catch {
            actionError = error.asAPIError.localizedDescription
        }
        pendingDelete = nil
    }
}

// MARK: - Pages column

private struct PagesListColumn: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model

    @Binding var selection: BioPage.ID?
    @Binding var isCreating: Bool
    @Binding var pendingDelete: BioPage?
    let setEnabled: (BioPage, Bool) -> Void
    let duplicate: (BioPage) -> Void

    var body: some View {
        @Bindable var bindable = model
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: "person.crop.square",
                title: String(localized: "No bio pages yet"),
                message: String(localized: "A bio page gathers your links, contact details and more at one address on \(app.addresses.publicHost)."),
                actionTitle: String(localized: "New Bio Page"),
                action: { isCreating = true }
            ),
            retry: { [list = model.list] in await list.refresh() }
        ) { _ in
            pageList
        }
        .background(Color.studioBg)
        .navigationTitle("Pages")
        .searchable(text: $bindable.searchText, prompt: Text("Search names and addresses"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("New Bio Page", systemImage: "plus")
                }
                .accessibilityIdentifier("pages.create")
            }
        }
    }

    private var pageList: some View {
        List(selection: $selection) {
            if let error = model.list.refreshError {
                RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                    .listRowSeparator(.hidden)
            }
            if model.visiblePages.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.visiblePages) { page in
                NavigationLink(value: page.id) {
                    BioPageRow(page: page)
                }
                .accessibilityIdentifier("pages.row.\(page.id)")
                .contextMenu { menu(for: page) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingDelete = page } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Pasteboard.copy(app.addresses.url(for: page.slug)?.absoluteString ?? "")
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
        .refreshable { [list = model.list] in await list.refresh() }
    }

    @ViewBuilder
    private func menu(for page: BioPage) -> some View {
        Button {
            selection = page.id
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }
        if let url = app.addresses.url(for: page.slug) {
            Button {
                Pasteboard.copy(url.absoluteString)
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Link(destination: url) {
                Label("Open Page", systemImage: "safari")
            }
        }
        if let card = app.addresses.cardURL(for: page.slug) {
            Link(destination: card) {
                Label("View Card", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
        }
        Divider()
        Button {
            setEnabled(page, !page.isEnabled)
        } label: {
            if page.isEnabled {
                Label("Turn Off", systemImage: "pause.circle")
            } else {
                Label("Turn On", systemImage: "play.circle")
            }
        }
        Button {
            duplicate(page)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) { pendingDelete = page } label: {
            Label("Delete…", systemImage: "trash")
        }
    }
}

/// Leading glyph, the page's name and address, trailing views.
struct BioPageRow: View {
    @Environment(AppModel.self) private var app
    let page: BioPage

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            RowGlyphTile(systemImage: "person.crop.square", isActive: page.isEnabled)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                HStack(spacing: StudioSpace.s2) {
                    Text(verbatim: page.title ?? app.addresses.display(for: page.slug))
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(2)
                    if !page.isEnabled {
                        StudioStatusPill(String(localized: "Off"), tone: .neutral)
                    } else if page.isLapsing {
                        StudioStatusPill(String(localized: "Lapsing"), tone: .warning)
                    }
                }
                HStack(spacing: StudioSpace.s2) {
                    if page.title != nil {
                        Text(verbatim: app.addresses.display(for: page.slug))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: StudioSpace.s2)
                    Label(page.clicks.grouped, systemImage: "eye")
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(page.clicks) views"))
                }
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Create

/// A new bio page: an optional name and its address. The web asks for the
/// address only; the name saves a step, since it is the first thing a page
/// needs. The address follows the name until it is edited.
struct CreatePageSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var onCreated: (BioPage) -> Void

    @State private var name = ""
    @State private var slug = ""
    @State private var slugIsEdited = false
    @State private var slugError: String?
    @State private var formError: String?
    @State private var isSaving = false
    @FocusState private var focus: Field?

    enum Field { case name, slug }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioSpace.s5) {
                    StudioTextField(
                        String(localized: "Name"),
                        text: $name,
                        placeholder: String(localized: "Alex Rivera"),
                        help: String(localized: "Shown at the top of the page. You can change it later.")
                    )
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .slug }

                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        StudioTextField(
                            String(localized: "Address"),
                            text: Binding(get: { slug }, set: { slug = $0; slugIsEdited = true }),
                            placeholder: "my-bio-page",
                            help: String(localized: "Letters, numbers, hyphens and underscores."),
                            errorMessage: slugError
                        )
                        .focused($focus, equals: .slug)
                        .plainEntry()
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }

                        Text(verbatim: app.addresses.display(for: slug.isEmpty ? "…" : slug))
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    FormErrorText(message: formError)
                }
                .padding(StudioSpace.s6)
                .readableWidth(560)
            }
            .background(Color.studioBg)
            .navigationTitle("New Bio Page")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await save() } }
                            .disabled(slug.isEmpty)
                    }
                }
            }
            .onChange(of: name) { _, newName in
                if !slugIsEdited { slug = Slug.suggestion(from: newName) }
                formError = nil
            }
            .onChange(of: slug) { slugError = nil; formError = nil }
            .defaultFocus($focus, .name)
            .interactiveDismissDisabled(isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }

    private func save() async {
        guard !isSaving else { return }
        if let problem = Slug.problem(with: slug) {
            slugError = Slug.message(for: problem)
            focus = .slug
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let page = try await model.create(slug: slug, title: name)
            Haptics.success()
            onCreated(page)
            dismiss()
        } catch let error as APIError {
            switch error {
            case .conflict:
                slugError = error.localizedDescription
                focus = .slug
            default:
                formError = error.localizedDescription
            }
        } catch {
            formError = error.localizedDescription
        }
    }
}
