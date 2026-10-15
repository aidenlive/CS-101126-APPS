import SwiftUI
import StudioKit
import CardsiteKit

/// Bio pages: a library of pages beside the open page's canvas editor.
/// On iPhone the split view collapses to a stack (pages → canvas). Opening
/// a page on iPad folds the pages column away to give the canvas the room;
/// the sidebar button or ✕ brings it back.
struct PagesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var selection: BioPage.ID? = nil
    @State private var editor: PageEditorModel? = nil
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var isCreating = false
    @State private var pendingDelete: BioPage? = nil
    @State private var actionError: ActionError? = nil
    @Environment(\.toasts) private var toasts

    struct ActionError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

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
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            #endif
        } detail: {
            if let editor {
                PageCanvasEditor(
                    editor: editor,
                    isCompact: isCompact,
                    actions: PageEditorActions(
                        duplicate: { page in Task { await duplicate(page) } },
                        delete: { page in pendingDelete = page },
                        close: closeEditor
                    )
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("page.editor")
                .id(editor.pageID)
            } else {
                SplitPlaceholder(systemImage: "person.crop.square",
                                 title: String(localized: "Select a page"),
                                 message: String(localized: "Its live preview opens here, ready to edit."))
                    #if os(macOS)
                    .navigationTitle("Pages")
                    #endif
            }
        }
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
            Button("Delete", role: .destructive) {
                Task { await delete(page) }
            }
        } message: { _ in
            Text("Anyone who opens or scans this address will get a not-found page, and every block on the page is deleted. This can’t be undone.")
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
        next.announce = { [toasts] message, variant in toasts?.show(message, variant: variant) }
        editor = next
        #if os(iOS)
        // iPad: the canvas, rail and inspector need the width. The Mac
        // keeps its sidebar; the window is the user's to size.
        if !isCompact {
            withAnimation(StudioAnimation.base) { columns = .detailOnly }
        }
        #endif
    }

    /// iPad's ✕: back to the pages, with the list showing.
    private func closeEditor() {
        selection = nil
        withAnimation(StudioAnimation.base) { columns = .all }
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
            actionError = ActionError(title: String(localized: "Couldn’t change the status"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func duplicate(_ page: BioPage) async {
        do {
            let copy = try await model.duplicate(page)
            Haptics.success()
            toasts?.show(
                String(localized: "Copied to \(app.addresses.display(for: copy.slug)). It’s off until you turn it on."),
                variant: .success
            )
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t duplicate"),
                                      message: error.asAPIError.localizedDescription)
        }
    }

    private func delete(_ page: BioPage) async {
        do {
            try await model.delete(page)
            if selection == page.id { selection = nil }
        } catch {
            actionError = ActionError(title: String(localized: "Couldn’t delete"),
                                      message: error.asAPIError.localizedDescription)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppDestination.pages.screenIdentifier)
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
                    .studioClearRow()
            }
            if model.visiblePages.isEmpty, !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
                    .studioClearRow()
            }
            ForEach(model.visiblePages) { page in
                NavigationLink(value: page.id) {
                    BioPageRow(page: page)
                }
                .accessibilityIdentifier("pages.row.\(page.id)")
                .contextMenu { ResourceMenuItems(actions: actions(for: page)) }
                .resourceSwipeActions(actions(for: page))
                .studioRowBackground(isSelected: selection == page.id)
            }
            if model.list.hasMore, model.searchText.isEmpty {
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

    private func actions(for page: BioPage) -> ResourceActionSet {
        ResourceActionSet(
            url: app.addresses.url(for: page.slug),
            cardURL: app.addresses.cardURL(for: page.slug),
            isEnabled: page.isEnabled,
            edit: { selection = page.id },
            duplicate: { duplicate(page) },
            setEnabled: { isOn in setEnabled(page, isOn) },
            delete: { pendingDelete = page }
        )
    }
}

/// A bio page in the shared row anatomy, led by a miniature of the page in
/// its own theme colours: the name with its state, the address and clicks.
/// At accessibility sizes the row stacks, like ``CardsiteResourceRow``.
struct BioPageRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    let page: BioPage

    var body: some View {
        let isStacked = typeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s2))
            : AnyLayout(HStackLayout(spacing: StudioSpace.s3))
        let address = app.addresses.display(for: page.slug)
        let state = ResourceState(isEnabled: page.isEnabled, isLapsing: page.isLapsing)

        layout {
            PageThumbnailTile(page: page)

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                titleLine(page.title ?? address, state: state, isStacked: isStacked)
                if page.title != nil {
                    Text(verbatim: address)
                        .lineLimit(isStacked ? 4 : 1)
                        .truncationMode(.middle)
                }
                if isStacked {
                    ClicksFigure(clicks: page.clicks)
                }
            }
            .studioText(.uiSm)
            .foregroundStyle(Color.studioText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if !isStacked {
                ClicksFigure(clicks: page.clicks)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize()
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .contentShape(Rectangle())
    }

    /// The same row height as ``CardsiteResourceRow``.
    private static var verticalPadding: CGFloat {
        #if os(macOS)
        return StudioSpace.s1
        #else
        return StudioSpace.s2
        #endif
    }

    @ViewBuilder
    private func titleLine(_ title: String, state: ResourceState, isStacked: Bool) -> some View {
        let name = Text(verbatim: title)
            .studioText(.ui)
            .foregroundStyle(Color.studioText)
        if isStacked {
            name.fixedSize(horizontal: false, vertical: true)
            if state != .live { state.pill }
        } else {
            HStack(spacing: StudioSpace.s2) {
                name
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if state != .live { state.pill.fixedSize() }
            }
        }
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
    @State private var slugError: String? = nil
    @State private var formError: String? = nil
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
                .readableWidth(.sheet)
            }
            .background(Color.studioBg)
            .navigationTitle("New Bio Page")
            #if os(iOS) || os(visionOS)
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
        .cardsiteSheet(.form)
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
