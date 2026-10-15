import SwiftUI
import StudioKit
import CardsiteKit

/*
 The bio page editor, as a canvas (Freeform).

 The live page is the content. On iPhone it fills the editor edge to edge
 and a glass tool palette floats at the bottom; on iPad and Mac it sits on
 the Studio canvas as a device-width artboard, with the palette as a rail
 in its own column so glass never covers the page.

 Selecting a block opens its inspector: a detented sheet on iPhone that
 leaves the canvas live behind it, `.inspector` on iPad and Mac. Blocks
 (the outline) is a sheet on iPhone and a popover from the rail elsewhere.
 Add Block, Theme and Page Settings are sheets everywhere.

 The toolbar keeps to three groups: ✕ (iPad), the Live status, and one
 "…" menu of page actions.
 */

/// What the editor asks of the Pages screen: page-level actions that
/// change the list.
struct PageEditorActions {
    var duplicate: (BioPage) -> Void
    var delete: (BioPage) -> Void
    /// iPad: the leading ✕ that closes the editor. Nil leaves it out.
    var close: (() -> Void)? = nil
}

/// The editor's sheets. Outline and block are iPhone only; iPad and Mac
/// show them as a popover and an inspector.
enum PageEditorSheet: Identifiable, Hashable {
    case library
    case outline
    case block(BioBlock.ID)
    case settings(PageSettingsView.Pane?)

    var id: String {
        switch self {
        case .library: return "library"
        case .outline: return "outline"
        case .block(let id): return "block-\(id)"
        case .settings(let pane): return "settings-\(pane?.rawValue ?? "")"
        }
    }

    var isCompactOnly: Bool {
        switch self {
        case .outline, .block: return true
        case .library, .settings: return false
        }
    }
}

struct PageCanvasEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var pages
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var editor: PageEditorModel
    let isCompact: Bool
    let actions: PageEditorActions

    @State private var sheet: PageEditorSheet? = nil
    @State private var isShowingOutline = false
    @State private var deferredPageAction: PageAction? = nil
    @State private var pendingDelete: BioBlock? = nil
    @State private var device: PageCanvasDevice = .phone
    @State private var isTogglingPage = false

    /// Page actions from the "…" menu. On iPhone the toolbar stays usable
    /// under a half-height sheet, so an action that presents something
    /// waits until that sheet has gone.
    enum PageAction { case duplicate, delete }

    var body: some View {
        withToolbar(titled)
        .background { BlockShortcuts(editor: editor) }
        .task { [editor, pages] in
            await editor.loadIfNeeded()
            await pages.loadCatalogIfNeeded()
        }
        .sheet(item: $sheet, onDismiss: sheetDidDismiss) { sheet in
            sheetContent(sheet)
        }
        #if os(visionOS)
        // visionOS has no `.inspector`: the block opens in a sheet there.
        .sheet(isPresented: inspectorIsPresented) {
            regularInspector
        }
        #else
        .inspector(isPresented: inspectorIsPresented) {
            regularInspector
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        #endif
        .pageBlockConflictAlert(editor: editor, isActive: !(isCompact && sheet != nil))
        .pageBlockDeleteDialog($pendingDelete, editor: editor)
        #if os(macOS)
        .onDeleteCommand {
            if let block = editor.selectedBlock { pendingDelete = block }
        }
        #endif
        .onChange(of: isCompact) { _, compact in
            if !compact, sheet?.isCompactOnly == true { sheet = nil }
            if compact { isShowingOutline = false }
        }
    }

    private var titled: some View {
        content
            .navigationTitle(title)
            .pageAddressSubtitle(subtitle)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private var title: String {
        guard let page = editor.page else { return String(localized: "Bio page") }
        return page.title ?? app.addresses.display(for: page.slug)
    }

    /// The address, under a page that has a name.
    private var subtitle: String? {
        guard let page = editor.page, page.title != nil else { return nil }
        return app.addresses.display(for: page.slug)
    }

    // MARK: Canvas

    @ViewBuilder
    private var content: some View {
        switch editor.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isCompact ? Color.studioBg : Color.studioCanvasBg)
                .accessibilityLabel(Text("Loading"))
        case .failed(let error):
            ErrorStateView(error: error) { [editor] in await editor.load() }
        case .loaded(let document):
            if isCompact {
                compactCanvas(document)
            } else {
                regularCanvas(document)
            }
        }
    }

    /// iPhone: the page edge to edge, the palette floating over its foot.
    private func compactCanvas(_ document: BioPageDocument) -> some View {
        PageCanvasPreview(
            page: document.page,
            revision: editor.previewRevision,
            bottomInset: paletteClearance,
            reload: { editor.reloadPreview() }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioCanvasArtboard)
        .safeAreaInset(edge: .top, spacing: 0) {
            banners(document.page)
                .padding(.horizontal, StudioSpace.s4)
                .padding(.top, hasBanners(document.page) ? StudioSpace.s2 : 0)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: StudioSpace.s3) {
                if document.blocks.isEmpty {
                    PageFirstBlockCallout { open(.add) }
                }
                palette(document, isVertical: false)
            }
            .padding(.horizontal, StudioSpace.s4)
            .padding(.bottom, StudioSpace.s2)
        }
        #if os(iOS)
        // An editing surface owns the bottom edge, as in Photos and
        // Freeform: the palette replaces the tab bar. The bar's
        // scroll-driven minimising also fought the web view's insets.
        .toolbar(.hidden, for: .tabBar)
        #endif
    }

    /// Room under the page's last block for the palette and its gap.
    private var paletteClearance: CGFloat {
        StudioLayout.tapTarget + StudioSpace.s1 * 2 + StudioSpace.s2 + StudioSpace.s4
    }

    /// iPad and Mac: the rail, then the artboard centred on the canvas,
    /// with the width switch under it.
    private func regularCanvas(_ document: BioPageDocument) -> some View {
        HStack(spacing: 0) {
            palette(document, isVertical: true)
                .padding(.leading, StudioLayout.floatInset)
                .padding(.vertical, StudioLayout.floatInset)

            VStack(spacing: StudioSpace.s4) {
                if hasBanners(document.page) {
                    banners(document.page)
                        .frame(maxWidth: device.width)
                }
                if document.blocks.isEmpty {
                    PageFirstBlockCallout { open(.add) }
                }
                StudioArtboard {
                    PageCanvasPreview(
                        page: document.page,
                        revision: editor.previewRevision,
                        reload: { editor.reloadPreview() }
                    )
                }
                .frame(maxWidth: device.width, maxHeight: .infinity)
                PageDeviceToggle(device: $device)
            }
            .padding(StudioSpace.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : StudioAnimation.out, value: device)
        }
        .background {
            ZStack {
                Color.studioCanvasBg
                StudioCanvasGrid()
            }
            .ignoresSafeArea()
        }
    }

    private func hasBanners(_ page: BioPage) -> Bool {
        editor.refreshError != nil || !page.isEnabled
    }

    /// Opaque banners above the page: a refresh that failed over stale
    /// data, and a page that is off.
    private func banners(_ page: BioPage) -> some View {
        VStack(spacing: StudioSpace.s2) {
            if let error = editor.refreshError {
                RefreshErrorBanner(error: error) { editor.dismissRefreshError() }
            }
            if !page.isEnabled {
                StudioBanner(
                    lead: String(localized: "This page is off."),
                    message: String(localized: "Visitors get a not-found page until you turn it on, and so does this preview."),
                    tone: .warning
                )
            }
        }
    }

    private func palette(_ document: BioPageDocument, isVertical: Bool) -> some View {
        PageToolPalette(
            page: document.page,
            isVertical: isVertical,
            isEmpty: document.blocks.isEmpty,
            selected: selectedTool,
            outlinePopover: isCompact ? nil : $isShowingOutline,
            perform: { open($0) }
        ) {
            BlockOutlineView(editor: editor, isInSheet: false) { id in
                editor.selection = id
            }
            .frame(minWidth: 320, idealWidth: 360, minHeight: 360, idealHeight: 520)
        }
    }

    private var selectedTool: PageCanvasTool? {
        if isShowingOutline { return .blocks }
        switch sheet {
        case .library: return .add
        case .outline: return .blocks
        case .settings(let pane): return pane == .theme ? .theme : .settings
        case .block, nil: return nil
        }
    }

    private func open(_ tool: PageCanvasTool) {
        switch tool {
        case .add: sheet = .library
        case .blocks:
            if isCompact {
                sheet = .outline
            } else {
                isShowingOutline.toggle()
            }
        case .theme: sheet = .settings(.theme)
        case .settings: sheet = .settings(nil)
        case .share: break
        }
    }

    /// Opens a block's inspector.
    private func inspect(_ id: BioBlock.ID) {
        editor.selection = id
        if isCompact { sheet = .block(id) }
    }

    private func add(_ type: BlockType) async -> Bool {
        let added = await editor.add(type)
        if added {
            // The new block opens in the inspector: on iPhone the library
            // sheet gives way to it; elsewhere the inspector column opens.
            if isCompact, let id = editor.selection {
                sheet = .block(id)
            } else {
                sheet = nil
            }
        }
        return added
    }

    // MARK: Sheets and inspector

    @ViewBuilder
    private func sheetContent(_ sheet: PageEditorSheet) -> some View {
        switch sheet {
        case .library:
            BlockLibrarySheet { type in await add(type) }
        case .settings(let pane):
            PageSettingsView(editor: editor, initialPane: pane)
        case .outline:
            NavigationStack {
                BlockOutlineView(
                    editor: editor,
                    isInSheet: true,
                    onSelect: { id in inspect(id) },
                    onAdd: { self.sheet = .library },
                    onClose: { self.sheet = nil }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
            .pageBlockConflictAlert(editor: editor, isActive: true)
        case .block(let id):
            PageInspectorSheet(editor: editor, blockID: id) { self.sheet = nil }
        }
    }

    private func sheetDidDismiss() {
        guard let action = deferredPageAction else { return }
        deferredPageAction = nil
        perform(action)
    }

    private var inspectorIsPresented: Binding<Bool> {
        Binding(
            get: { !isCompact && editor.selection != nil && editor.state.value != nil },
            set: { isPresented in if !isPresented { editor.selection = nil } }
        )
    }

    @ViewBuilder
    private var regularInspector: some View {
        if let id = editor.selection {
            #if os(macOS)
            BlockInspectorView(editor: editor, blockID: id)
                .id(id)
            #else
            NavigationStack {
                BlockInspectorView(editor: editor, blockID: id, close: { editor.selection = nil })
            }
            .id(id)
            #endif
        }
    }

    // MARK: Toolbar

    /// ✕ (iPad), the Live status, and "…": three groups. On 26 a fixed
    /// spacer keeps the text status apart from the symbol menu.
    @ViewBuilder
    private func withToolbar<V: View>(_ view: V) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            view.toolbar {
                liveItem
                ToolbarSpacer(.fixed, placement: trailingPlacement)
                moreItem
            }
        } else {
            view.toolbar {
                liveItem
                moreItem
            }
        }
        #elseif os(visionOS)
        view.toolbar {
            closeItem
            liveItem
            moreItem
        }
        #else
        if #available(iOS 26.0, *) {
            view.toolbar {
                closeItem
                liveItem
                ToolbarSpacer(.fixed, placement: trailingPlacement)
                moreItem
            }
        } else {
            view.toolbar {
                closeItem
                liveItem
                moreItem
            }
        }
        #endif
    }

    private var trailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    #if !os(macOS)
    @ToolbarContentBuilder
    private var closeItem: some ToolbarContent {
        if !isCompact, let close = actions.close {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    close()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .help("Close this page")
            }
        }
    }
    #endif

    @ToolbarContentBuilder
    private var liveItem: some ToolbarContent {
        ToolbarItem(placement: trailingPlacement) {
            if let page = editor.page {
                PageLiveMenu(page: page, isBusy: isTogglingPage, showsTitle: !isCompact) { isOn in
                    Task { await setPageEnabled(isOn) }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var moreItem: some ToolbarContent {
        ToolbarItem(placement: trailingPlacement) {
            Menu {
                if let page = editor.page {
                    pageMenu(page)
                }
            } label: {
                Label("Page Actions", systemImage: "ellipsis")
            }
            .disabled(editor.page == nil)
            .accessibilityIdentifier("page.editor.more")
        }
    }

    @ViewBuilder
    private func pageMenu(_ page: BioPage) -> some View {
        Button {
            runPageAction(.duplicate)
        } label: {
            Label("Duplicate Page", systemImage: ResourceVerb.duplicate.systemImage)
        }
        if let card = app.addresses.cardURL(for: page.slug) {
            Button { openURL(card) } label: { ResourceVerb.showCard.label }
        }
        if let url = app.addresses.url(for: page.slug) {
            Button { openURL(url) } label: { ResourceVerb.openInBrowser.label }
        }
        Divider()
        Button(role: .destructive) {
            runPageAction(.delete)
        } label: {
            Label("Delete Page…", systemImage: ResourceVerb.delete.systemImage)
        }
    }

    private func runPageAction(_ action: PageAction) {
        if sheet != nil {
            deferredPageAction = action
            sheet = nil
        } else {
            perform(action)
        }
    }

    private func perform(_ action: PageAction) {
        guard let page = editor.page else { return }
        switch action {
        case .duplicate: actions.duplicate(page)
        case .delete: actions.delete(page)
        }
    }

    private func setPageEnabled(_ isOn: Bool) async {
        isTogglingPage = true
        defer { isTogglingPage = false }
        do {
            try await editor.savePage(BioPageChanges(isEnabled: isOn))
        } catch {
            editor.announce(String(localized: "Couldn’t update this page. \(error.asAPIError.localizedDescription)"), .error)
        }
    }
}

// MARK: - Live status

/// The page's state in the toolbar ("● Live" / "Off"), opening a menu that
/// says what it means and turns it on or off.
private struct PageLiveMenu: View {
    let page: BioPage
    let isBusy: Bool
    /// iPhone: the dot alone. A title-and-icon label in the crowded compact
    /// bar (title, address, two items) kept the toolbar re-laying out
    /// forever after a push (CI sample: ToolbarBridge.preferencesDidChange
    /// → UIKitBarButtonItem.updateHost → trait updates, 100% CPU).
    var showsTitle = true
    let setEnabled: (Bool) -> Void

    var body: some View {
        let state = ResourceState(isEnabled: page.isEnabled, isLapsing: page.isLapsing)
        Menu {
            Section {
                Button {
                    setEnabled(!page.isEnabled)
                } label: {
                    ResourceVerb.toggle(isEnabled: page.isEnabled).label
                }
            } header: {
                Text(page.isEnabled
                     ? String(localized: "Anyone with the address can open this page.")
                     : String(localized: "Off: visitors get a not-found page."))
            }
        } label: {
            Label {
                Text(state.title)
            } icon: {
                Image(systemName: page.isEnabled ? "circle.fill" : "circle.dashed")
                    .foregroundStyle(page.isEnabled ? Color.studioAccentLine : Color.studioText3)
            }
            .labelStyle(showsTitle ? AnyLabelStyle.titleAndIcon : AnyLabelStyle.iconOnly)
        }
        .disabled(isBusy)
        .accessibilityLabel(Text("Status"))
        .accessibilityValue(Text(state.title))
        .accessibilityIdentifier("page.editor.status")
    }
}

// MARK: - Inspector sheet (iPhone)

/// The block inspector as a Maps-style sheet: three detents, the canvas
/// interactive behind it up to half height, and the system's glass sheet
/// material (no `presentationBackground`).
private struct PageInspectorSheet: View {
    let editor: PageEditorModel
    let blockID: BioBlock.ID
    let close: () -> Void

    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            BlockInspectorView(editor: editor, blockID: blockID, isOnGlass: true, close: close)
        }
        .presentationDetents([.height(300), .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .pageBlockConflictAlert(editor: editor, isActive: true)
    }
}

// MARK: - Outline

/// Blocks, top to bottom: reorder by dragging, show or hide each one, and
/// tap one to edit it. A sheet on iPhone; the Blocks popover on iPad and Mac.
struct BlockOutlineView: View {
    let editor: PageEditorModel
    let isInSheet: Bool
    let onSelect: (BioBlock.ID) -> Void
    var onAdd: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var pendingDelete: BioBlock? = nil

    var body: some View {
        chrome(
            List(selection: Binding(
                get: { editor.selection },
                set: { id in if let id { onSelect(id) } }
            )) {
                if !isInSheet {
                    header.studioClearRow()
                }
                Section {
                    if editor.blocks.isEmpty {
                        emptyState.studioClearRow()
                    }
                    ForEach(editor.blocks) { block in
                        row(block)
                    }
                    .onMove { source, destination in
                        editor.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    if editor.blocks.count > 1 {
                        Text("Drag to reorder. The page shows blocks top to bottom.")
                    }
                }
            }
            .outlineSurface(onGlass: isInSheet)
            .refreshable { [editor] in await editor.load() }
        )
        .pageBlockDeleteDialog($pendingDelete, editor: editor)
        #if os(macOS)
        .onDeleteCommand {
            if let block = editor.selectedBlock { pendingDelete = block }
        }
        .background { BlockShortcuts(editor: editor) }
        #endif
        .accessibilityIdentifier("page.editor.outline")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s2) {
            Text("Blocks")
                .studioText(.titleSm)
                .foregroundStyle(Color.studioText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: StudioSpace.s2)
            Text(editor.blocks.count.grouped)
                .studioText(.uiSm)
                .monospacedDigit()
                .foregroundStyle(Color.studioText3)
                .accessibilityLabel(Text("\(editor.blocks.count) blocks"))
        }
    }

    private var emptyState: some View {
        StudioEmptyState(
            systemImage: "square.stack.3d.up",
            title: String(localized: "Add your first block"),
            message: onAdd == nil
                ? String(localized: "Use Add to pick one from the library. It appears on your page as soon as it’s added.")
                : String(localized: "Pick one from the library. It appears on your page as soon as it’s added."),
            compact: true
        ) {
            if let onAdd {
                StudioButton(String(localized: "Add Block"), systemImage: "plus", variant: .primary) {
                    onAdd()
                }
            }
        }
    }

    private func row(_ block: BioBlock) -> some View {
        let type = editor.blockType(for: block)
        return BlockRow(
            block: block,
            type: type,
            summary: BlockSummary.line(for: block, draft: editor.drafts[block.id], type: type),
            isDirty: editor.hasUnsavedChanges(block),
            isBusy: editor.busyBlockIDs.contains(block.id),
            isEnabled: Binding(
                get: { editor.block(block.id)?.isEnabled ?? block.isEnabled },
                set: { isOn in Task { await editor.setEnabled(block, isOn) } }
            )
        )
        .tag(block.id)
        .studioRowBackground(isSelected: editor.selection == block.id)
        .contextMenu {
            Button {
                onSelect(block.id)
            } label: {
                ResourceVerb.edit.label
            }
            BlockActionItems(editor: editor, block: block) { pendingDelete = block }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = block } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await editor.duplicate(block) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.studioInfo)
            .disabled(editor.isDuplicateLocked(block))
        }
        .accessibilityAction(named: Text("Edit")) { onSelect(block.id) }
    }

    /// In a sheet: a title, ✕ and Add. In a popover: none (the list has
    /// its own header, and a popover has no bar).
    @ViewBuilder
    private func chrome<V: View>(_ list: V) -> some View {
        if isInSheet {
            list
                .navigationTitle("Blocks")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if let onClose {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                onClose()
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                        }
                    }
                    if let onAdd {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                onAdd()
                            } label: {
                                Label("Add Block", systemImage: "plus")
                            }
                        }
                    }
                }
        } else {
            list
        }
    }
}

private extension View {
    /// The outline's background: the sheet's glass on 26 (rows keep their
    /// opaque Studio surface), the Studio page elsewhere.
    @ViewBuilder
    func outlineSurface(onGlass: Bool) -> some View {
        if onGlass {
            if #available(iOS 26.0, macOS 26.0, *) {
                self
                    .scrollContentBackground(.hidden)
                    .tint(Color.studioAccentLine)
            } else {
                studioList()
            }
        } else {
            studioList()
        }
    }

    /// The page's address under its name: `navigationSubtitle` on Mac and
    /// on iOS 26.
    @ViewBuilder
    func pageAddressSubtitle(_ subtitle: String?) -> some View {
        if let subtitle {
            #if os(macOS)
            navigationSubtitle(subtitle)
            #elseif os(iOS)
            if #available(iOS 26.0, *) {
                navigationSubtitle(subtitle)
            } else {
                self
            }
            #else
            self
            #endif
        } else {
            self
        }
    }
}

// MARK: - Rows

/// One block: glyph, type name, a line from its main field, and its switch.
struct BlockRow: View {
    let block: BioBlock
    let type: BlockType?
    let summary: String?
    let isDirty: Bool
    let isBusy: Bool
    @Binding var isEnabled: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StudioSpace.s3) {
                    HStack(alignment: .top, spacing: StudioSpace.s3) {
                        BlockGlyphTile(type: block.type, color: type?.color)
                        text
                    }
                    toggle.labelsHidden()
                }
            } else {
                HStack(spacing: StudioSpace.s3) {
                    BlockGlyphTile(type: block.type, color: type?.color)
                    text
                    Spacer(minLength: StudioSpace.s2)
                    toggle.labelsHidden()
                }
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .contain)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            HStack(spacing: StudioSpace.s2) {
                Text(type?.name ?? BlockFieldInference.humanized(block.type))
                    .studioText(.ui)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.studioText)
                if isDirty {
                    StudioStatusPill(String(localized: "Unsaved"), tone: .warning)
                }
                if !isEnabled {
                    StudioStatusPill(String(localized: "Hidden"), tone: .neutral)
                }
            }
            Text(summary ?? String(localized: "Nothing filled in yet"))
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var toggle: some View {
        Toggle("Show on page", isOn: $isEnabled)
            .toggleStyle(.switch)
            .tint(.studioAccent)
            .disabled(isBusy)
    }
}

/// A block's commands, for its context menu and the inspector's menu.
struct BlockActionItems: View {
    let editor: PageEditorModel
    let block: BioBlock
    let requestDelete: () -> Void

    var body: some View {
        Button {
            Task { await editor.duplicate(block) }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .disabled(editor.isDuplicateLocked(block))
        Button {
            editor.move(block, by: -1)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        .disabled(!editor.canMove(block, by: -1))
        Button {
            editor.move(block, by: 1)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        .disabled(!editor.canMove(block, by: 1))
        Button {
            Task { await editor.setEnabled(block, !block.isEnabled) }
        } label: {
            if block.isEnabled {
                Label("Hide Block", systemImage: "eye.slash")
            } else {
                Label("Show Block", systemImage: "eye")
            }
        }
        Divider()
        Button(role: .destructive, action: requestDelete) {
            Label("Delete…", systemImage: "trash")
        }
    }
}

/// Copy Link, Open in Browser, Share, Show Card and the web editor, for
/// the palette's Share tool.
struct PageShareItems: View {
    @Environment(AppModel.self) private var app
    let page: BioPage

    var body: some View {
        ResourceMenuItems(actions: ResourceActionSet(
            url: app.addresses.url(for: page.slug),
            cardURL: app.addresses.cardURL(for: page.slug)
        ))
        Divider()
        Link(destination: app.configuration.bioPageEditorURL(pageID: page.id)) {
            Label("Open in Web Editor", systemImage: "arrow.up.forward.square")
        }
    }
}

// MARK: - Alerts

extension View {
    /// The 409 from a block write: someone else saved first. Reload drops
    /// this block's draft and loads what is stored now. `isActive` keeps
    /// exactly one presenter live: the sheet when one is up, else the canvas.
    func pageBlockConflictAlert(editor: PageEditorModel, isActive: Bool) -> some View {
        alert(
            "This block changed",
            isPresented: Binding(
                get: { isActive && editor.conflict != nil },
                set: { isPresented in if !isPresented { editor.conflict = nil } }
            ),
            presenting: editor.conflict
        ) { conflict in
            Button("Reload") {
                Task { await editor.reloadAfterConflict(conflict) }
            }
            Button("Not Now", role: .cancel) { editor.conflict = nil }
        } message: { conflict in
            if let name = conflict.editorName {
                Text("\(name) changed this block since you opened it. Reload to see their version, then reapply your edit.")
            } else {
                Text("Someone changed this block since you opened it. Reload to see their version, then reapply your edit.")
            }
        }
    }

    /// Confirms deleting a block. Each host (outline, inspector, canvas)
    /// owns its own `pending` block; `willDelete` runs as the delete starts
    /// (the inspector closes itself).
    func pageBlockDeleteDialog(
        _ pending: Binding<BioBlock?>,
        editor: PageEditorModel,
        willDelete: (() -> Void)? = nil
    ) -> some View {
        confirmationDialog(
            "Delete this block?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { isPresented in if !isPresented { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { block in
            Button("Delete Block", role: .destructive) {
                willDelete?()
                Task { await editor.delete(block) }
            }
        } message: { _ in
            Text("It comes off the public page straight away. This can’t be undone.")
        }
    }
}

// MARK: - Keyboard

/// Block commands for a hardware keyboard: ⌘D duplicates, ⌥⌘↑ and ⌥⌘↓
/// move the selected block, ⌘R reloads the preview. (Delete is the delete
/// command on Mac.) The buttons are invisible; the same actions are in each
/// block's menus.
private struct BlockShortcuts: View {
    let editor: PageEditorModel

    var body: some View {
        let block = editor.selectedBlock
        ZStack {
            Button("Duplicate Block") {
                if let block { Task { await editor.duplicate(block) } }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(block.map { editor.isDuplicateLocked($0) } ?? true)

            Button("Move Block Up") {
                if let block { editor.move(block, by: -1) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(block.map { !editor.canMove($0, by: -1) } ?? true)

            Button("Move Block Down") {
                if let block { editor.move(block, by: 1) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(block.map { !editor.canMove($0, by: 1) } ?? true)

            Button("Reload Preview") {
                editor.reloadPreview()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(editor.page == nil)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
