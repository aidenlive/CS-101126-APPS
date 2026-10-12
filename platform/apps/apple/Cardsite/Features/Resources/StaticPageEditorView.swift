import SwiftUI
import StudioKit
import CardsiteKit
#if os(iOS)
import UIKit
#endif

/// Everything the static page editor edits. `picked` is a new HTML or ZIP
/// file to upload; nil keeps the stored one.
struct StaticPageForm: Equatable {
    var address: AddressForm
    var picked: PickedFile?
    var gate: GateForm
    /// What is stored now ("HTML page", "ZIP site"); nil while creating.
    let currentDescription: String?
    let savedExpiration: String?

    init() {
        address = AddressForm()
        picked = nil
        gate = GateForm()
        currentDescription = nil
        savedExpiration = nil
    }

    init(resource: ManagedResource) {
        address = AddressForm(slug: resource.slug, domainID: resource.domainID)
        picked = nil
        gate = GateForm(gate: resource.gate)
        currentDescription = Self.describe(resource.staticPage)
        savedExpiration = resource.gate.expirationURL
    }

    static func describe(_ page: StaticPageSettings) -> String {
        switch page.kind {
        case "zip": return String(localized: "A site from a ZIP file")
        case "markdown": return String(localized: "A Markdown page")
        case "svg": return String(localized: "An SVG image")
        default: return String(localized: "An HTML page")
        }
    }

    func validate() -> [ResourceField: String] {
        var errors: [ResourceField: String] = [:]
        address.validate(into: &errors)
        if currentDescription == nil, picked == nil {
            errors[.file] = String(localized: "Choose an HTML or ZIP file to upload.")
        }
        gate.validate(into: &errors, savedExpiration: savedExpiration)
        return errors
    }

    var draft: StaticPageDraft {
        StaticPageDraft(slug: address.trimmedSlug, domainID: address.domainID, gate: gate.gate, password: gate.password)
    }
}

/// A static page: an uploaded HTML page, or a ZIP of a site, served from an
/// address you choose. ZIP sites are usually built on a computer, so on
/// iPhone the editor says so, and still allows it.
struct StaticPageEditorView: View {
    @State private var model: ResourceEditorModel<StaticPageForm>
    let list: ResourceListModel
    let onCreated: (ResourceItem) -> Void

    init(item: ResourceItem?, list: ResourceListModel, onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.list = list
        self.onCreated = onCreated
        _model = State(initialValue: ResourceEditorModel(
            item: item,
            blank: StaticPageForm(),
            list: list,
            makeForm: { item in item.link.map(StaticPageForm.init(resource:)) ?? StaticPageForm() },
            validate: { $0.validate() },
            submit: { [client = list.client] form, item in
                if let saved = item?.link {
                    return .link(try await client.updateStaticPage(id: saved.id, form.draft, savedGate: saved.gate,
                                                                   file: form.picked?.multipart))
                }
                guard let file = form.picked else { throw PickedFile.Problem.unreadable }
                return .link(try await client.createStaticPage(form.draft, file: file.multipart))
            }
        ))
    }

    var body: some View {
        @Bindable var model = model
        ResourceEditorScaffold(kind: .staticPage, model: model, list: list, onCreated: onCreated) { _ in
            EmptyView()
        } fields: {
            Section {
                ResourceAddressRows(kind: .staticPage, address: $model.form.address, list: list, isNew: model.isNew,
                                    savedAddress: model.savedForm.address, error: model.errors[.slug],
                                    prompt: String(localized: "my-page"))
            } header: {
                EditorSectionHeader(String(localized: "Address"))
            } footer: {
                ResourceAddressFooter(list: list, isNew: model.isNew)
            }
            .editorRowBackground()

            Section {
                if isPhone {
                    ResourceNote(
                        systemImage: "desktopcomputer",
                        message: String(localized: "ZIP sites are usually built on a computer. You can still upload one from Files here, as long as index.html is at its root.")
                    )
                }
                ResourceFileRows(
                    picked: $model.form.picked,
                    currentName: model.form.currentDescription,
                    allowedTypes: PickedFile.staticPageTypes,
                    allowedMIMETypes: ResourceUploadRules.staticMIMETypes,
                    accepts: PickedFile.staticPageAccepts,
                    allowsPhotos: false,
                    error: model.errors[.file]
                )
            } header: {
                EditorSectionHeader(model.isNew ? String(localized: "HTML or ZIP file") : String(localized: "Replace file"))
            } footer: {
                if !model.isNew {
                    Text("Leave empty to keep the current file and change only the address and settings.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .editorRowBackground()

            GatingSection(
                password: $model.form.gate.password,
                hasPassword: model.savedForm.gate.hasPassword,
                clicksLimit: $model.form.gate.clicksLimitText,
                expirationURL: $model.form.gate.expirationURL,
                sensitiveContent: $model.form.gate.sensitiveContent,
                passwordLocked: !list.options.allowsPasswordProtection,
                errors: .init(password: model.errors[.password], clicksLimit: model.errors[.clicksLimit],
                              expirationURL: model.errors[.expirationURL])
            )
        }
        .onChange(of: model.form) { model.formChanged() }
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

#Preview("Edit static page") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.staticPage, items: [.link(.previewStatic)], client: app.client)
    NavigationStack {
        StaticPageEditorView(item: .link(.previewStatic), list: list)
    }
    .environment(app)
}

#Preview("New static page") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.staticPage, items: [], client: app.client)
    NavigationStack {
        StaticPageEditorView(item: nil, list: list)
    }
    .environment(app)
}
