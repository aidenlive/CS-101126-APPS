import SwiftUI
import StudioKit
import CardsiteKit
#if os(iOS)
import UIKit
#endif

/// Bio pages on iPad and Mac: a library of pages beside the open page's
/// canvas editor. Opening a page on iPad folds the pages column away to
/// give the canvas the room; the sidebar button or ✕ brings it back.
///
/// iPhone uses ``PagesStackView`` instead, pushed onto Library's stack, so
/// this split view never nests inside another stack.
struct PagesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model
    @Environment(\.toasts) private var toasts
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var selection: BioPage.ID? = nil
    @State private var editor: PageEditorModel? = nil
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var isCreating = false
    @State private var pendingDelete: BioPage? = nil
    @State private var actionError: PageActionError? = nil

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    private var actions: PageListActions {
        PageListActions(app: app, pages: model, toasts: toasts)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            PagesListColumn(
                selection: $selection,
                isCreating: $isCreating,
                pendingDelete: $pendingDelete,
                pushesEditor: false,
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
        .pageListDialogs(pendingDelete: $pendingDelete, actionError: $actionError) { page in
            Task { await delete(page) }
        }
    }

    // MARK: Editor lifecycle

    private func open(_ id: BioPage.ID?) {
        editor = actions.editor(for: id, replacing: editor)
        #if os(iOS)
        // iPad: the canvas, rail and inspector need the width. The Mac
        // keeps its sidebar; the window is the user's to size.
        if editor != nil, !isCompact {
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
        actionError = await actions.setEnabled(page, isOn, editor: editor)
    }

    private func duplicate(_ page: BioPage) async {
        actionError = await actions.duplicate(page)
    }

    private func delete(_ page: BioPage) async {
        let error = await actions.delete(page)
        if error == nil, selection == page.id { selection = nil }
        actionError = error
        pendingDelete = nil
    }
}

// MARK: - iPhone

/// Bio pages on iPhone: the page list, then the canvas editor pushed onto
/// Library's stack as a ``PageEditorRoute`` in the router's path.
///
/// Not `navigationDestination(item:)`: inside a stack bound to a path, a
/// tapped row's item push kept writing back to the path, and the shell's
/// tab view rebuilt its tab bar every frame (CI sample: 100% CPU in
/// `UITabBarController _rebuildTabBarItems`, the app unresponsive).
///
/// A stack-free destination: it brings no NavigationStack of its own, so
/// Library can push it without nesting stacks. The editor runs in its
/// iPhone mode: the page edge to edge, the floating palette, detented
/// sheets, and the system back button instead of ✕.
struct PagesStackView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellRouter.self) private var router
    @Environment(PagesModel.self) private var model
    @Environment(\.toasts) private var toasts
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var selection: BioPage.ID? = nil
    /// The open page's editor. A reference the pushed view observes
    /// itself: CI showed a `navigationDestination` inside Library's stack
    /// kept the content it was pushed with, so an editor made a moment
    /// after the push never replaced the spinner.
    @State private var slot = PageEditorSlot()
    private var editor: PageEditorModel? {
        get { slot.editor }
        nonmutating set { slot.editor = newValue }
    }
    @State private var isCreating = false
    @State private var pendingDelete: BioPage? = nil
    @State private var actionError: PageActionError? = nil
    /// Library's depth with the editor on top, to notice the pop.
    @State private var editorDepth: Int? = nil

    /// The canvas's iPhone mode on every iPhone (landscape included), and
    /// in a compact iPad window.
    private var isCompact: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone || sizeClass == .compact
        #else
        return false
        #endif
    }

    private var actions: PageListActions {
        PageListActions(app: app, pages: model, toasts: toasts)
    }

    var body: some View {
        PagesListColumn(
            selection: $selection,
            isCreating: $isCreating,
            pendingDelete: $pendingDelete,
            pushesEditor: true,
            setEnabled: { page, isOn in Task { await setEnabled(page, isOn) } },
            duplicate: { page in Task { await duplicate(page) } }
        )
        .navigationDestination(for: PageEditorRoute.self) { route in
            editorView(for: route.pageID)
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        #if DEBUG
        // `-CardsiteOpenFirstPage YES`: CI's editor diagnosis.
        .onChange(of: model.list.items.first?.id, initial: true) { _, id in
            guard FixtureMode.isEnabled, UserDefaults.standard.bool(forKey: "CardsiteOpenFirstPage"),
                  selection == nil, let id else { return }
            selection = id
        }
        #endif
        .onChange(of: selection) { _, id in
            editor = actions.editor(for: id, replacing: editor)
            guard let id else { return }
            if let depth = editorDepth, router.libraryPath.count == depth {
                // Another page while one is open (a created page, a deep
                // link): swap the top route rather than stacking editors.
                router.libraryPath.removeLast()
            }
            router.libraryPath.append(PageEditorRoute(pageID: id))
            editorDepth = router.libraryPath.count
        }
        .onChange(of: router.libraryPath.count) { _, count in
            // Back from the editor: the page list is on top again.
            if let depth = editorDepth, count < depth {
                editorDepth = nil
                selection = nil
            }
        }
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
        .pageListDialogs(pendingDelete: $pendingDelete, actionError: $actionError) { page in
            Task { await delete(page) }
        }
    }

    private func editorView(for id: BioPage.ID) -> some View {
        PageEditorDestination(
            slot: slot,
            pageID: id,
            isCompact: isCompact,
            actions: PageEditorActions(
                duplicate: { page in Task { await duplicate(page) } },
                delete: { page in pendingDelete = page }
            )
        )
    }

    private func setEnabled(_ page: BioPage, _ isOn: Bool) async {
        actionError = await actions.setEnabled(page, isOn, editor: editor)
    }

    private func duplicate(_ page: BioPage) async {
        actionError = await actions.duplicate(page)
    }

    /// Deleting the open page pops its editor.
    private func delete(_ page: BioPage) async {
        let error = await actions.delete(page)
        if error == nil, selection == page.id, let depth = editorDepth,
           router.libraryPath.count >= depth {
            // Pops the editor; the depth check above clears the selection.
            router.libraryPath.removeLast(router.libraryPath.count - depth + 1)
        }
        actionError = error
        pendingDelete = nil
    }
}

// MARK: - Shared page actions

/// A failed page action, as an alert.
struct PageActionError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// What both Pages layouts do to a page: open its editor, turn it on or
/// off, duplicate and delete it. Each action returns the error to show.
@MainActor
struct PageListActions {
    let app: AppModel
    let pages: PagesModel
    let toasts: StudioToastCenter?

    /// The editor for `id`: `current` when it is already that page's, a new
    /// one otherwise, nil for no page. A page left with unsaved drafts
    /// saves them.
    func editor(for id: BioPage.ID?, replacing current: PageEditorModel?) -> PageEditorModel? {
        if let current, current.pageID != id, current.hasAnyUnsavedChanges {
            Task { await current.saveAllDrafts() }
        }
        guard let id else { return nil }
        if let current, current.pageID == id { return current }
        let next = PageEditorModel(pageID: id, pages: pages)
        next.onError = app.handle
        next.announce = { [toasts] message, variant in toasts?.show(message, variant: variant) }
        return next
    }

    func setEnabled(_ page: BioPage, _ isOn: Bool, editor: PageEditorModel?) async -> PageActionError? {
        do {
            if let editor, editor.pageID == page.id {
                try await editor.savePage(BioPageChanges(isEnabled: isOn))
            } else {
                try await pages.setEnabled(page, isOn)
            }
            return nil
        } catch {
            return PageActionError(title: String(localized: "Couldn’t change the status"),
                                   message: error.asAPIError.localizedDescription)
        }
    }

    func duplicate(_ page: BioPage) async -> PageActionError? {
        do {
            let copy = try await pages.duplicate(page)
            Haptics.success()
            toasts?.show(
                String(localized: "Copied to \(app.addresses.display(for: copy.slug)). It’s off until you turn it on."),
                variant: .success
            )
            return nil
        } catch {
            return PageActionError(title: String(localized: "Couldn’t duplicate"),
                                   message: error.asAPIError.localizedDescription)
        }
    }

    func delete(_ page: BioPage) async -> PageActionError? {
        do {
            try await pages.delete(page)
            return nil
        } catch {
            return PageActionError(title: String(localized: "Couldn’t delete"),
                                   message: error.asAPIError.localizedDescription)
        }
    }
}

private extension View {
    /// The delete confirmation and the action-error alert both layouts show.
    func pageListDialogs(
        pendingDelete: Binding<BioPage?>,
        actionError: Binding<PageActionError?>,
        delete: @escaping (BioPage) -> Void
    ) -> some View {
        confirmationDialog(
            "Delete this bio page?",
            isPresented: Binding(get: { pendingDelete.wrappedValue != nil },
                                 set: { if !$0 { pendingDelete.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete.wrappedValue
        ) { page in
            Button("Delete", role: .destructive) {
                delete(page)
            }
        } message: { _ in
            Text("Anyone who opens or scans this address will get a not-found page, and every block on the page is deleted. This can’t be undone.")
        }
        .alert(
            actionError.wrappedValue?.title ?? "",
            isPresented: Binding(get: { actionError.wrappedValue != nil },
                                 set: { if !$0 { actionError.wrappedValue = nil } }),
            presenting: actionError.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}

// MARK: - Pages column

/// The page list. In the split view it drives the selection; pushed on
/// iPhone (`pushesEditor`), each row is a button that sets the selection
/// the host pushes the editor for.
private struct PagesListColumn: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model

    @Binding var selection: BioPage.ID?
    @Binding var isCreating: Bool
    @Binding var pendingDelete: BioPage?
    let pushesEditor: Bool
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
            if pushesEditor {
                pageList(List { rows })
            } else {
                pageList(List(selection: $selection) { rows })
            }
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

    private func pageList<L: View>(_ list: L) -> some View {
        list
            .studioList()
            .refreshable { [list = model.list] in await list.refresh() }
    }

    @ViewBuilder
    private var rows: some View {
        if let error = model.list.refreshError {
            RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                .studioClearRow()
        }
        if model.visiblePages.isEmpty, !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
                .studioClearRow()
        }
        ForEach(model.visiblePages) { page in
            row(page)
                .accessibilityIdentifier("pages.row.\(page.id)")
                .contextMenu { ResourceMenuItems(actions: actions(for: page)) }
                .resourceSwipeActions(actions(for: page))
                .studioRowBackground(isSelected: !pushesEditor && selection == page.id)
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

    @ViewBuilder
    private func row(_ page: BioPage) -> some View {
        if pushesEditor {
            Button {
                selection = page.id
            } label: {
                HStack(spacing: StudioSpace.s2) {
                    BioPageRow(page: page)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Color.studioText4)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the page editor"))
        } else {
            NavigationLink(value: page.id) {
                BioPageRow(page: page)
            }
        }
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

/// Holds the pushed page's editor so the pushed view can observe it.
@MainActor
@Observable
final class PageEditorSlot {
    var editor: PageEditorModel?
}

/// The page editor pushed from the iPhone's Pages list: the canvas once
/// its model exists, a spinner for the moment before.
private struct PageEditorDestination: View {
    let slot: PageEditorSlot
    let pageID: BioPage.ID
    let isCompact: Bool
    let actions: PageEditorActions

    var body: some View {
        if let editor = slot.editor, editor.pageID == pageID {
            PageCanvasEditor(editor: editor, isCompact: isCompact, actions: actions)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("page.editor")
                .id(editor.pageID)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.studioBg)
                .accessibilityLabel(Text("Loading"))
        }
    }
}

/// The iPhone page editor's place in Library's path.
struct PageEditorRoute: Hashable, Codable, Sendable {
    let pageID: BioPage.ID
}
