import SwiftUI
import StudioKit
import CardsiteKit

/// The selected block's properties, generated from the server's field
/// specs and grouped into calm sections. Edits collect in a draft; Save
/// sends the whole `settings` object with the block's version.
struct BlockInspectorView: View {
    @Environment(PagesModel.self) private var pages
    let editor: PageEditorModel
    let blockID: BioBlock.ID

    var body: some View {
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

    private func content(_ block: BioBlock) -> some View {
        let type = editor.blockType(for: block)
        let fields = type?.fields ?? BlockFieldInference.fields(for: block.settings)
        let isDirty = editor.hasUnsavedChanges(block)
        let isSaving = editor.savingBlockIDs.contains(block.id)

        return Form {
            Section {
                InspectorHeader(block: block, type: type, isDirty: isDirty)
                if let type, type.isPremium, !pages.allows(PagesModel.Capability.premiumBlocks) {
                    Text("Your plan doesn't include this block type. This one keeps working and you can still edit it; new ones can't be added.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if type == nil, pages.blockTypes.error != nil {
                Section {
                    StudioBanner(
                        lead: String(localized: "Block types didn't load."),
                        message: String(localized: "Fields are shown from what this block stores. Try again for the full set."),
                        tone: .warning
                    )
                    Button("Try Again") {
                        Task { await pages.loadCatalog() }
                    }
                }
            }
            ForEach(InspectorGroup.groups(for: fields)) { group in
                Section {
                    ForEach(group.fields) { field in
                        BlockFieldView(field: field, value: binding(field.name, block: block), pageID: editor.pageID)
                    }
                } header: {
                    Text(group.title)
                }
            }
            if fields.isEmpty {
                Section {
                    Text("This block has nothing to set. It shows on the page as it is.")
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText2)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.studioBg)
        .navigationTitle(type?.name ?? BlockFieldInference.humanized(block.type))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isDirty, !isSaving {
                ToolbarItem(placement: .automatic) {
                    Button("Revert") { editor.revert(block) }
                        .help("Discard unsaved changes to this block")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel("Saving")
                } else {
                    Button("Save") {
                        Task { await save(block.id) }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
                }
            }
        }
    }

    private func save(_ id: BioBlock.ID) async {
        // Save the freshest copy: its version may have moved since the
        // view was drawn (an enable toggle, a reorder).
        guard let current = editor.block(id) else { return }
        if await editor.save(current) {
            Haptics.success()
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

/// Glyph, type name and category, with the block's state beside them.
private struct InspectorHeader: View {
    let block: BioBlock
    let type: BlockType?
    let isDirty: Bool

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            BlockGlyphTile(type: block.type, color: type?.color)
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(type?.name ?? BlockFieldInference.humanized(block.type))
                    .studioText(.titleSm)
                    .foregroundStyle(Color.studioText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BlockCategory.title(type?.category ?? "standard"))
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                HStack(spacing: StudioSpace.s2) {
                    if isDirty {
                        StudioStatusPill(String(localized: "Unsaved"), tone: .warning)
                    }
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
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
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
