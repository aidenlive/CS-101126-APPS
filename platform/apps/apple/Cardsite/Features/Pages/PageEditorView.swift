import SwiftUI
import StudioKit
import CardsiteKit

// The bio page editor, as two split-view columns: the block list, and the
// inspector or preview beside it. On iPhone the split view collapses to a
// stack (list → inspector) and Preview opens as a sheet.

// MARK: - Block list column

struct BlockListColumn: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var pages
    @Bindable var editor: PageEditorModel
    let isCompact: Bool

    @State private var isAddingBlock = false
    @State private var isEditingSettings = false
    @State private var isPreviewing = false
    @State private var pendingDelete: BioBlock? = nil
    @State private var isTogglingPage = false

    var body: some View {
        Group {
            switch editor.state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading")
            case .failed(let error):
                ErrorStateView(error: error) { [editor] in await editor.load() }
            case .loaded(let document):
                blockList(document)
            }
        }
        .background(Color.studioBg)
        .navigationTitle(title)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .background { BlockShortcuts(editor: editor) }
        .task { [editor, pages] in
            await editor.loadIfNeeded()
            await pages.loadCatalogIfNeeded()
        }
        .sheet(isPresented: $isAddingBlock) {
            BlockLibrarySheet { type in await editor.add(type) }
        }
        .sheet(isPresented: $isEditingSettings) {
            PageSettingsView(editor: editor)
        }
        .sheet(isPresented: $isPreviewing) {
            if let page = editor.page {
                NavigationStack {
                    PagePreviewPane(page: page, revision: editor.previewRevision, isFramed: false)
                        .navigationTitle("Preview")
                        #if os(iOS) || os(visionOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPreviewing = false }
                            }
                        }
                }
            }
        }
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { block in
            Button("Delete Block", role: .destructive) {
                Task { await editor.delete(block) }
            }
        } message: { _ in
            Text("It comes off the public page straight away. This can’t be undone.")
        }
    }

    private var title: String {
        guard let page = editor.page else { return String(localized: "Bio page") }
        return page.title ?? page.slug
    }

    // MARK: List

    private func blockList(_ document: BioPageDocument) -> some View {
        List(selection: $editor.selection) {
            if let error = editor.refreshError {
                RefreshErrorBanner(error: error) { editor.dismissRefreshError() }
                    .studioClearRow()
            }
            Section {
                PageStatusRow(page: document.page, isToggling: isTogglingPage) { isOn in
                    Task { await setPageEnabled(isOn) }
                }
            }
            Section {
                if document.blocks.isEmpty {
                    StudioEmptyState(
                        systemImage: "square.stack.3d.up",
                        title: String(localized: "Add your first block"),
                        message: String(localized: "Pick one from the library. It appears on your page as soon as it’s added, and you fill it in here."),
                        compact: true
                    ) {
                        StudioButton(String(localized: "Add Block"), systemImage: "plus", variant: .primary) {
                            isAddingBlock = true
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(document.blocks) { block in
                    BlockRow(
                        block: block,
                        type: editor.blockType(for: block),
                        summary: BlockSummary.line(for: block, draft: editor.drafts[block.id], type: editor.blockType(for: block)),
                        isDirty: editor.hasUnsavedChanges(block),
                        isBusy: editor.busyBlockIDs.contains(block.id),
                        isEnabled: Binding(
                            get: { editor.block(block.id)?.isEnabled ?? block.isEnabled },
                            set: { isOn in Task { await editor.setEnabled(block, isOn) } }
                        )
                    )
                    .tag(block.id)
                    .contextMenu { menu(for: block) }
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
                    }
                }
                .onMove { source, destination in
                    editor.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                if !document.blocks.isEmpty {
                    Text("Blocks")
                }
            } footer: {
                if document.blocks.count > 1 {
                    Text("Drag to reorder. The page shows blocks top to bottom.")
                }
            }
        }
        .tint(Color.studioAccentLine)
        .refreshable { [editor] in await editor.load() }
        #if os(macOS)
        .onDeleteCommand {
            if let block = editor.selectedBlock { pendingDelete = block }
        }
        #endif
    }

    @ViewBuilder
    private func menu(for block: BioBlock) -> some View {
        Button {
            Task { await editor.duplicate(block) }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .disabled(isDuplicateLocked(block))
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
        Button(role: .destructive) { pendingDelete = block } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    /// A duplicate is a create, so a premium type the plan lacks can't be copied.
    private func isDuplicateLocked(_ block: BioBlock) -> Bool {
        guard let type = editor.blockType(for: block), type.isPremium else { return false }
        return !pages.allows(PagesModel.Capability.premiumBlocks)
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

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isAddingBlock = true
            } label: {
                Label("Add Block", systemImage: "plus")
            }
            .disabled(editor.page == nil)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                if isCompact {
                    isPreviewing = true
                } else {
                    editor.detailMode = .preview
                }
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .disabled(editor.page == nil)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                isEditingSettings = true
            } label: {
                Label("Page Settings", systemImage: "slider.horizontal.3")
            }
            .disabled(editor.page == nil)
        }
    }
}

// MARK: - Rows

/// The page itself, above its blocks: address, views and the live switch.
private struct PageStatusRow: View {
    @Environment(AppModel.self) private var app
    let page: BioPage
    let isToggling: Bool
    let setEnabled: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s2) {
                Text(verbatim: app.addresses.display(for: page.slug))
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: StudioSpace.s2)
                Label(page.clicks.grouped, systemImage: "eye")
                    .studioText(.uiSm)
                    .monospacedDigit()
                    .foregroundStyle(Color.studioText3)
                    .accessibilityLabel(Text("\(page.clicks) views"))
                PageShareMenu(page: page)
                    .labelStyle(.iconOnly)
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
            }
            EditorToggleRow(
                label: String(localized: "Live"),
                help: page.isEnabled
                    ? String(localized: "Anyone with the address can open this page.")
                    : String(localized: "Off: visitors get a not-found page."),
                isOn: Binding(get: { [isOn = page.isEnabled] in isOn }, set: { [setEnabled] in setEnabled($0) })
            )
            .disabled(isToggling)
        }
        .padding(.vertical, StudioSpace.s1)
    }
}

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

/// Copy Link, Open in Browser, Share, Show Card and the web editor for the page.
struct PageShareMenu: View {
    @Environment(AppModel.self) private var app
    let page: BioPage

    var body: some View {
        Menu {
            ResourceMenuItems(actions: ResourceActionSet(
                url: app.addresses.url(for: page.slug),
                cardURL: app.addresses.cardURL(for: page.slug)
            ))
            Divider()
            Link(destination: app.configuration.bioPageEditorURL(pageID: page.id)) {
                Label("Open in Web Editor", systemImage: "arrow.up.forward.square")
            }
        } label: {
            Label("Share and Open", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - Keyboard

/// Block commands for a hardware keyboard: ⌘D duplicates, ⌥⌘↑ and ⌥⌘↓
/// move the selected block. (Delete is the list's delete command on Mac.)
/// The buttons are invisible; the same actions are in each row's menu.
private struct BlockShortcuts: View {
    let editor: PageEditorModel

    var body: some View {
        let block = editor.selectedBlock
        ZStack {
            Button("Duplicate Block") {
                if let block { Task { await editor.duplicate(block) } }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(block == nil)

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
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Detail column

/// Inspector or preview. On iPad and Mac a segmented control switches
/// between them; on iPhone this column only ever shows the inspector.
struct EditorDetailColumn: View {
    @Bindable var editor: PageEditorModel
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact || editor.detailMode == .inspector {
                if let id = editor.selection {
                    BlockInspectorView(editor: editor, blockID: id)
                        .id(id)
                } else {
                    ContentUnavailableView(
                        "Nothing selected",
                        systemImage: "cursorarrow.click",
                        description: Text("Choose a block to edit it here. The page’s title, theme and SEO are in Page Settings.")
                    )
                    .background(Color.studioBg)
                }
            } else if let page = editor.page {
                PagePreviewPane(page: page, revision: editor.previewRevision)
                    .navigationTitle("Preview")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            if !isCompact {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $editor.detailMode) {
                        Text("Block").tag(PageEditorModel.DetailMode.inspector)
                        Text("Preview").tag(PageEditorModel.DetailMode.preview)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }
}
