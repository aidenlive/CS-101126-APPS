import SwiftUI
import StudioKit
import CardsiteKit

/// The selected block's properties, generated from the server's field
/// specs and grouped into calm sections. Edits collect in a draft; Save
/// (the one prominent action, ✓) sends the whole `settings` object with
/// the block's version, and the header says Unsaved, Saving or Saved.
///
/// Hosts: a detented sheet on iPhone (`isOnGlass`, so the system's sheet
/// material shows between the opaque rows), `.inspector` on iPad and Mac.
struct BlockInspectorView: View {
    @Environment(PagesModel.self) private var pages
    let editor: PageEditorModel
    let blockID: BioBlock.ID
    var isOnGlass = false
    /// The ✕ that closes the inspector; nil on Mac, where the inspector
    /// closes with the selection.
    var close: (() -> Void)? = nil

    @State private var pendingDelete: BioBlock? = nil

    var body: some View {
        Group {
            if let block = editor.block(blockID) {
                content(block)
            } else {
                ContentUnavailableView(
                    "This block is gone",
                    systemImage: "square.dashed",
                    description: Text("It was deleted, here or somewhere else.")
                )
            }
        }
        // A deleted block's inspector closes with it.
        .pageBlockDeleteDialog($pendingDelete, editor: editor, willDelete: close)
    }

    private func content(_ block: BioBlock) -> some View {
        let type = editor.blockType(for: block)
        let fields = type?.fields ?? BlockFieldInference.fields(for: block.settings)
        let isDirty = editor.hasUnsavedChanges(block)
        let isSaving = editor.savingBlockIDs.contains(block.id)

        return Form {
            Section {
                InspectorHeader(
                    block: block,
                    type: type,
                    status: InspectorSaveStatus(isDirty: isDirty, isSaving: isSaving,
                                                isSaved: editor.savedBlockID == block.id),
                    revert: { editor.revert(block) }
                ) {
                    BlockActionItems(editor: editor, block: block) { pendingDelete = block }
                }
                if let type, type.isPremium, !pages.allows(PagesModel.Capability.premiumBlocks) {
                    Text("Your plan doesn’t include this block type. This one keeps working and you can still edit it; new ones can’t be added.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .studioRowBackground()
            if type == nil, pages.blockTypes.error != nil {
                Section {
                    StudioBanner(
                        lead: String(localized: "Block types didn’t load."),
                        message: String(localized: "Fields are shown from what this block stores. Try again for the full set."),
                        tone: .warning
                    )
                    Button("Try Again") {
                        Task { await pages.loadCatalog() }
                    }
                }
                .studioRowBackground()
            }
            ForEach(InspectorGroup.groups(for: fields)) { group in
                Section {
                    ForEach(group.fields) { field in
                        BlockFieldView(field: field, value: binding(field.name, block: block), pageID: editor.pageID)
                    }
                } header: {
                    Text(group.title)
                }
                .studioRowBackground()
            }
            if fields.isEmpty {
                Section {
                    Text("This block has nothing to set. It shows on the page as it is.")
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText2)
                }
                .studioRowBackground()
            }
        }
        .inspectorSurface(onGlass: isOnGlass)
        #if os(iOS) || os(visionOS)
        .navigationTitle(type?.name ?? BlockFieldInference.humanized(block.type))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let close {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        close()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
            ToolbarItem(placement: savePlacement) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel(Text("Saving"))
                } else {
                    Button {
                        Task { await save(block.id) }
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
                    .help("Save this block")
                    .accessibilityIdentifier("page.editor.save")
                }
            }
        }
    }

    /// ✓ is the sheet's confirmation on iOS. On Mac the inspector's items
    /// join the window toolbar, where a confirmation placement doesn't apply.
    private var savePlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .confirmationAction
        #endif
    }

    private func save(_ id: BioBlock.ID) async {
        // Save the freshest copy: its version may have moved since the
        // view was drawn (an enable toggle, a reorder).
        guard let current = editor.block(id) else { return }
        if await editor.save(current) {
            Haptics.success()
            AccessibilityNotification.Announcement(String(localized: "Saved")).post()
        }
    }

    private func binding(_ name: String, block: BioBlock) -> Binding<JSONValue?> {
        let id = block.id
        return Binding(
            get: { editor.block(id).flatMap { editor.value(name, in: $0) } },
            set: { newValue in
                guard let current = editor.block(id) else { return }
                editor.setValue(newValue, for: name, in: current)
            }
        )
    }
}

private extension View {
    /// On the iPhone sheet (26): the sheet's glass between opaque Studio
    /// rows. Elsewhere, the Studio form on the page background.
    @ViewBuilder
    func inspectorSurface(onGlass: Bool) -> some View {
        if onGlass {
            if #available(iOS 26.0, macOS 26.0, *) {
                self
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .studioText(.ui)
                    .tint(Color.studioAccentLine)
            } else {
                studioForm()
            }
        } else {
            studioForm()
        }
    }
}

/// Where the block's edits stand.
struct InspectorSaveStatus: Equatable {
    var isDirty: Bool
    var isSaving: Bool
    var isSaved: Bool
}

/// Glyph, type name and category, the save state, and the block's menu.
private struct InspectorHeader<Actions: View>: View {
    let block: BioBlock
    let type: BlockType?
    let status: InspectorSaveStatus
    let revert: () -> Void
    @ViewBuilder let actions: () -> Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            BlockGlyphTile(type: block.type, color: type?.color)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(type?.name ?? BlockFieldInference.humanized(block.type))
                        .studioText(.titleSm)
                        .foregroundStyle(Color.studioText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BlockCategory.title(type?.category ?? "standard"))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: StudioSpace.s2) {
                    if !block.isEnabled {
                        StudioStatusPill(String(localized: "Hidden"), tone: .neutral)
                    }
                    if type?.hasStatistics == true, block.clicks > 0 {
                        Label(block.clicks.grouped, systemImage: "cursorarrow.click")
                            .studioText(.uiSm)
                            .monospacedDigit()
                            .foregroundStyle(Color.studioText3)
                            .accessibilityLabel(Text("\(block.clicks) clicks"))
                    }
                }
                saveState
                    .animation(reduceMotion ? nil : StudioAnimation.base, value: status)
            }
            Spacer(minLength: 0)
            Menu {
                actions()
            } label: {
                Label("Block Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                    .frame(minWidth: StudioLayout.tapTarget, minHeight: StudioLayout.tapTarget)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, StudioSpace.s1)
    }

    /// Unsaved (with Revert), Saving…, or a moment of Saved.
    @ViewBuilder
    private var saveState: some View {
        if status.isSaving {
            HStack(spacing: StudioSpace.s2) {
                ProgressView().controlSize(.small)
                Text("Saving…")
            }
            .studioText(.uiSm)
            .foregroundStyle(Color.studioText3)
            .transition(.opacity)
        } else if status.isDirty {
            HStack(spacing: StudioSpace.s2) {
                StudioStatusPill(String(localized: "Unsaved"), tone: .warning)
                Button("Revert", action: revert)
                    .buttonStyle(.borderless)
                    .studioText(.uiSm)
                    .help("Discard unsaved changes to this block")
            }
            .transition(.opacity)
        } else if status.isSaved {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioSuccess)
                .transition(.opacity)
        }
    }
}

/// Inspector sections. Fields keep the registry's order inside each one.
struct InspectorGroup: Identifiable {
    let id: String
    let title: String
    var fields: [BlockField]

    /// Select fields that only shape the look (`border_radius`, `columns`,
    /// …) sit with the colours rather than with the words.
    private static let appearanceSelects: Set<String> = [
        "border_radius", "columns", "text_alignment", "theme", "size", "heading_type",
    ]

    static func groups(for fields: [BlockField]) -> [InspectorGroup] {
        var content = InspectorGroup(id: "content", title: String(localized: "Content"), fields: [])
        var media = InspectorGroup(id: "media", title: String(localized: "Media"), fields: [])
        var appearance = InspectorGroup(id: "appearance", title: String(localized: "Appearance"), fields: [])
        var options = InspectorGroup(id: "options", title: String(localized: "Options"), fields: [])
        var web = InspectorGroup(id: "web", title: String(localized: "Edited on the web"), fields: [])

        for field in fields {
            switch field.fieldKind {
            case .image, .file:
                media.fields.append(field)
            case .color:
                appearance.fields.append(field)
            case .select where appearanceSelects.contains(field.name):
                appearance.fields.append(field)
            case .boolean:
                options.fields.append(field)
            case .structured:
                web.fields.append(field)
            default:
                content.fields.append(field)
            }
        }
        return [content, media, appearance, options, web].filter { !$0.fields.isEmpty }
    }
}
