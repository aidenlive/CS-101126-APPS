#if DEBUG
import SwiftUI
import StudioKit
import CardsiteKit

/// Sample bio pages and blocks, shaped like fixtures 24b, 24g and 24j.
@MainActor
enum PagesPreviewData {
    static let page = BioPage(
        id: 24,
        slug: "alex",
        settings: ["title": "Alex Rivera", "description": "Designer in Lisbon", "background_type": "color"],
        clicks: 1_284,
        pixelIDs: [3]
    )

    static let pages: [BioPage] = [
        page,
        BioPage(id: 25, slug: "spring-menu", settings: ["title": "Spring Menu"], clicks: 312),
        BioPage(id: 26, slug: "alex-copy", clicks: 0, isEnabled: false, directoryIsEnabled: false),
    ]

    static let types: [BlockType] = [
        BlockType(type: "link", name: "Link", category: "standard", hasStatistics: true, fields: [
            BlockField(name: "name", kind: "text", label: "Label"),
            BlockField(name: "location_url", kind: "url", label: "URL"),
            BlockField(name: "background_color", kind: "color", label: "Background Color"),
            BlockField(name: "border_radius", kind: "select", label: "Border Radius", options: [
                BlockFieldOption(value: "0", label: "None"),
                BlockFieldOption(value: "8", label: "Medium"),
                BlockFieldOption(value: "9999", label: "Full"),
            ]),
            BlockField(name: "open_in_new_tab", kind: "boolean", label: "Open in New Tab"),
        ]),
        BlockType(type: "heading", name: "Heading", category: "standard", fields: [
            BlockField(name: "heading", kind: "text", label: "Heading"),
            BlockField(name: "heading_type", kind: "select", label: "Heading Type", options: [
                BlockFieldOption(value: "h1", label: "H1"),
                BlockFieldOption(value: "h2", label: "H2"),
            ]),
        ]),
        BlockType(type: "image", name: "Image", category: "standard", fields: [
            BlockField(name: "image", kind: "image", label: "Image"),
            BlockField(name: "alt", kind: "text", label: "Alt Text"),
        ]),
        BlockType(type: "email_collector", name: "Email Collector", category: "forms", fields: [
            BlockField(name: "name", kind: "text", label: "Name"),
            BlockField(name: "notifications", kind: "notifications-picker", label: "Notifications"),
        ]),
        BlockType(type: "faq", name: "FAQ", category: "advanced",
                  capability: BlockType.premiumCapability, fields: [
            BlockField(name: "items", kind: "markers-list", label: "Items"),
            BlockField(name: "border_width", kind: "number", label: "Border Width"),
        ]),
        BlockType(type: "countdown", name: "Countdown", category: "advanced",
                  capability: BlockType.premiumCapability, fields: [
            BlockField(name: "counter_end_date", kind: "datetime", label: "End Date"),
            BlockField(name: "expired_text", kind: "text", label: "Expired Text"),
        ]),
    ]

    static let blocks: [BioBlock] = [
        BioBlock(id: 8, linkID: 24, type: "heading", settings: ["heading": "Hello", "heading_type": "h2"], order: 0, version: 2),
        BioBlock(id: 7, linkID: 24, type: "link", locationURL: "https://example.com/shop",
                 settings: ["name": "Shop now", "open_in_new_tab": true], clicks: 96, order: 1, version: 3),
        BioBlock(id: 9, linkID: 24, type: "email_collector", settings: ["name": "Newsletter"],
                 isEnabled: false, order: 2, version: 2),
        BioBlock(id: 10, linkID: 24, type: "faq",
                 settings: ["items": [["title": "Opening hours?", "content": "Nine to five."]]], order: 3, version: 1),
    ]

    static func app() -> AppModel { AppModel(configuration: .preview) }

    static func pagesModel(capabilities: PlanCapabilities? = .unrestricted) -> PagesModel {
        let model = PagesModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
        model.seedForPreview(pages: pages, types: types, capabilities: capabilities)
        return model
    }

    static func editor(_ pages: PagesModel) -> PageEditorModel {
        let editor = PageEditorModel(pageID: page.id, pages: pages, document: BioPageDocument(page: page, blocks: blocks))
        editor.selection = 7
        return editor
    }
}

#Preview("Pages") {
    PagesScreen()
        .environment(PagesPreviewData.app())
        .environment(PagesPreviewData.pagesModel())
}

#Preview("Blocks") {
    let pages = PagesPreviewData.pagesModel()
    NavigationStack {
        BlockListColumn(editor: PagesPreviewData.editor(pages), isCompact: true)
    }
    .environment(PagesPreviewData.app())
    .environment(pages)
}

#Preview("Inspector") {
    let pages = PagesPreviewData.pagesModel()
    NavigationStack {
        BlockInspectorView(editor: PagesPreviewData.editor(pages), blockID: 7)
    }
    .environment(PagesPreviewData.app())
    .environment(pages)
}

#Preview("Inspector, web-only field") {
    let pages = PagesPreviewData.pagesModel(capabilities: PlanCapabilities(settings: [:]))
    NavigationStack {
        BlockInspectorView(editor: PagesPreviewData.editor(pages), blockID: 10)
    }
    .environment(PagesPreviewData.app())
    .environment(pages)
}

#Preview("Add a Block, premium locked") {
    BlockLibrarySheet(onAdd: { _ in true })
        .environment(PagesPreviewData.app())
        .environment(PagesPreviewData.pagesModel(capabilities: PlanCapabilities(settings: [:])))
}

#Preview("Page Settings") {
    let pages = PagesPreviewData.pagesModel()
    PageSettingsView(editor: PagesPreviewData.editor(pages))
        .environment(PagesPreviewData.app())
        .environment(pages)
}

#Preview("Theme") {
    let pages = PagesPreviewData.pagesModel()
    NavigationStack {
        PageSettingsSectionView(section: .theme, settings: PageSettingsModel(editor: PagesPreviewData.editor(pages)))
    }
    .environment(PagesPreviewData.app())
    .environment(pages)
}

#Preview("Block row, largest text") {
    List {
        BlockRow(block: PagesPreviewData.blocks[1], type: PagesPreviewData.types[0], summary: "Shop now",
                 isDirty: true, isBusy: false, isEnabled: .constant(true))
        BlockRow(block: PagesPreviewData.blocks[2], type: PagesPreviewData.types[3], summary: "Newsletter",
                 isDirty: false, isBusy: false, isEnabled: .constant(false))
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("New Bio Page") {
    CreatePageSheet(onCreated: { _ in })
        .environment(PagesPreviewData.app())
        .environment(PagesPreviewData.pagesModel())
}
#endif
