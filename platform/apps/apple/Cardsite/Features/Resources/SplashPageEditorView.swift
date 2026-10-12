import SwiftUI
import StudioKit
import CardsiteKit

extension SplashPageDraft {
    /// A new splash page as the web starts one: unlocks after 5 seconds.
    static var blank: SplashPageDraft { SplashPageDraft() }

    /// What the editor offers for `link_unlock_seconds`.
    static let unlockSecondsRange: ClosedRange<Int> = 1...300

    func validate() -> [ResourceField: String] {
        var errors: [ResourceField: String] = [:]
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.name] = String(localized: "A name is required.")
        }
        if !(SplashPageDraft.unlockSecondsRange ~= linkUnlockSeconds) {
            errors[.unlock] = String(localized: "Choose between \(SplashPageDraft.unlockSecondsRange.lowerBound) and \(SplashPageDraft.unlockSecondsRange.upperBound) seconds.")
        }
        let buttonURL = secondaryButtonURL.trimmingCharacters(in: .whitespaces)
        if !buttonURL.isEmpty, Destination.normalized(buttonURL) == nil {
            errors[.secondaryURL] = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
        }
        return errors
    }

    /// The draft to send: the secondary URL with `https://` added.
    var normalized: SplashPageDraft {
        var draft = self
        let buttonURL = secondaryButtonURL.trimmingCharacters(in: .whitespaces)
        if !buttonURL.isEmpty { draft.secondaryButtonURL = Destination.normalized(buttonURL)?.absoluteString ?? buttonURL }
        return draft
    }
}

/// A splash page: the Basic tab of the web's editor. Ads and custom code
/// are left out because the web stores them but never renders them; any
/// that were set on the web are kept as they are on save.
struct SplashPageEditorView: View {
    @State private var model: ResourceEditorModel<SplashPageDraft>
    let list: ResourceListModel
    let onCreated: (ResourceItem) -> Void

    init(item: ResourceItem?, list: ResourceListModel, onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.list = list
        self.onCreated = onCreated
        _model = State(initialValue: ResourceEditorModel(
            item: item,
            blank: SplashPageDraft.blank,
            list: list,
            makeForm: { item in item.splash.map(SplashPageDraft.init(page:)) ?? SplashPageDraft.blank },
            validate: { $0.validate() },
            submit: { [client = list.client] form, item in
                if let item {
                    return .splash(try await client.updateSplashPage(id: item.id, form.normalized))
                }
                return .splash(try await client.createSplashPage(form.normalized))
            }
        ))
    }

    var body: some View {
        @Bindable var model = model
        ResourceEditorScaffold(kind: .splash, model: model, list: list, onCreated: onCreated) { _ in
            EmptyView()
        } fields: {
            Section {
                EditorTextField(String(localized: "Name"), text: $model.form.name,
                                prompt: String(localized: "My splash page"),
                                help: String(localized: "Only you see this, when choosing a splash page for a link."),
                                error: model.errors[.name])
                EditorTextField(String(localized: "Title"), text: $model.form.title,
                                prompt: String(localized: "You are being redirected..."))
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Description")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .accessibilityHidden(true)
                    TextField(String(localized: "Description"), text: $model.form.description,
                              prompt: Text("Optional description shown on the splash page"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...6)
                        .studioText(.ui)
                }
                .padding(.vertical, StudioSpace.s1)
            } header: {
                EditorSectionHeader(String(localized: "Basic"))
            }
            .editorRowBackground()

            Section {
                Stepper(value: $model.form.linkUnlockSeconds, in: SplashPageDraft.unlockSecondsRange) {
                    LabeledContent {
                        Text("\(model.form.linkUnlockSeconds) s")
                            .monospacedDigit()
                            .foregroundStyle(Color.studioText2)
                    } label: {
                        Text("Unlock after (seconds)")
                    }
                }
                .accessibilityValue(Text("\(model.form.linkUnlockSeconds) seconds"))
                EditorFieldFootnote(help: nil, error: model.errors[.unlock])
                Toggle(isOn: $model.form.autoRedirect) {
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text("Auto redirect")
                        Text("Auto-redirect after countdown")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                EditorSectionHeader(String(localized: "Countdown"))
            }
            .editorRowBackground()

            Section {
                EditorTextField(String(localized: "Secondary button text"), text: $model.form.secondaryButtonName,
                                prompt: String(localized: "Skip"))
                EditorTextField(String(localized: "Secondary button URL"), text: $model.form.secondaryButtonURL,
                                prompt: "https://example.com", kind: .url, error: model.errors[.secondaryURL])
            } header: {
                EditorSectionHeader(String(localized: "Secondary button"))
            } footer: {
                if !model.form.otherSettings.isEmpty {
                    Text("Ads and custom code added on the web are kept as they are.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .editorRowBackground()
        }
        .onChange(of: model.form) { model.formChanged() }
    }
}

#Preview("Edit splash page") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.splash, items: [.splash(.preview)], client: app.client)
    NavigationStack {
        SplashPageEditorView(item: .splash(.preview), list: list)
    }
    .environment(app)
}

#Preview("New splash page") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.splash, items: [], client: app.client)
    NavigationStack {
        SplashPageEditorView(item: nil, list: list)
    }
    .environment(app)
}
