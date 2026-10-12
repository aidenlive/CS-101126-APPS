import SwiftUI
import StudioKit
import CardsiteKit

/// Everything the file link editor edits. `picked` is a new file to upload;
/// nil keeps the stored one.
struct FileLinkForm: Equatable {
    var address: AddressForm
    var picked: PickedFile?
    var forceDownload: Bool
    var gate: GateForm
    /// The stored file's name; nil while creating.
    let currentFileName: String?
    /// The stored expiration URL, which multipart updates can't remove.
    let savedExpiration: String?

    init() {
        address = AddressForm()
        picked = nil
        forceDownload = false
        gate = GateForm()
        currentFileName = nil
        savedExpiration = nil
    }

    init(resource: ManagedResource) {
        address = AddressForm(slug: resource.slug, domainID: resource.domainID)
        picked = nil
        forceDownload = resource.file.forceDownload
        gate = GateForm(gate: resource.gate)
        currentFileName = resource.file.fileName
        savedExpiration = resource.gate.expirationURL
    }

    func validate() -> [ResourceField: String] {
        var errors: [ResourceField: String] = [:]
        address.validate(into: &errors)
        if currentFileName == nil, picked == nil {
            errors[.file] = String(localized: "Choose a file to upload.")
        }
        gate.validate(into: &errors, savedExpiration: savedExpiration)
        return errors
    }

    var draft: FileLinkDraft {
        FileLinkDraft(slug: address.trimmedSlug, domainID: address.domainID, forceDownload: forceDownload,
                      gate: gate.gate, password: gate.password)
    }
}

/// A file link: a hosted file at an address you choose. Upload from Files
/// or Photos (checked on the device: type and 10 MB), replace it later, and
/// choose whether it downloads or opens in the browser.
struct FileLinkEditorView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ResourceEditorModel<FileLinkForm>
    let list: ResourceListModel
    let onCreated: (ResourceItem) -> Void

    init(item: ResourceItem?, list: ResourceListModel, onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.list = list
        self.onCreated = onCreated
        _model = State(initialValue: ResourceEditorModel(
            item: item,
            blank: FileLinkForm(),
            list: list,
            makeForm: { item in item.link.map(FileLinkForm.init(resource:)) ?? FileLinkForm() },
            validate: { $0.validate() },
            submit: { [client = list.client] form, item in
                if let saved = item?.link {
                    return .link(try await client.updateFileLink(id: saved.id, form.draft, savedGate: saved.gate,
                                                                 file: form.picked?.multipart))
                }
                guard let file = form.picked else { throw PickedFile.Problem.unreadable }
                return .link(try await client.createFileLink(form.draft, file: file.multipart))
            }
        ))
    }

    var body: some View {
        @Bindable var model = model
        ResourceEditorScaffold(kind: .file, model: model, list: list, onCreated: onCreated) { item in
            if let url = list.publicURL(for: item, addresses: app.addresses) {
                Link(destination: url) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(StudioButtonStyle(.outline))
                .accessibilityHint(Text("Opens the file’s address, as visitors get it"))
            }
        } fields: {
            Section {
                ResourceAddressRows(kind: .file, address: $model.form.address, list: list, isNew: model.isNew,
                                    savedAddress: model.savedForm.address, error: model.errors[.slug],
                                    prompt: String(localized: "my-file"))
            } header: {
                EditorSectionHeader(String(localized: "Address"))
            } footer: {
                ResourceAddressFooter(list: list, isNew: model.isNew)
            }
            .studioRowBackground()

            Section {
                ResourceFileRows(
                    picked: $model.form.picked,
                    currentName: model.form.currentFileName,
                    allowedTypes: PickedFile.fileLinkTypes,
                    allowedMIMETypes: ResourceUploadRules.fileMIMETypes,
                    accepts: PickedFile.fileLinkAccepts,
                    allowsPhotos: true,
                    error: model.errors[.file]
                )
                Toggle(isOn: $model.form.forceDownload) {
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text("Force download")
                        Text("Instead of opening in the browser.")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                EditorSectionHeader(model.isNew ? String(localized: "File") : String(localized: "Replace file"))
            } footer: {
                if !model.isNew {
                    Text("Leave empty to keep the current file and change only the address and settings.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .studioRowBackground()

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
}

#Preview("Edit file link") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.file, items: [.link(.previewFile)], client: app.client)
    NavigationStack {
        FileLinkEditorView(item: .link(.previewFile), list: list)
    }
    .environment(app)
}

#Preview("New file link") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.file, items: [], client: app.client)
    NavigationStack {
        FileLinkEditorView(item: nil, list: list)
    }
    .environment(app)
}
