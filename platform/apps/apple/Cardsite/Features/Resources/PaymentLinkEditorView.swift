import SwiftUI
import StudioKit
import CardsiteKit

/// Everything the payment link editor edits.
struct PaymentLinkForm: Equatable {
    var address: AddressForm
    var checkoutURL: String
    var settings: PaymentLinkSettings
    var gate: GateForm

    init() {
        address = AddressForm()
        checkoutURL = ""
        settings = PaymentLinkSettings()
        gate = GateForm()
    }

    init(resource: ManagedResource) {
        address = AddressForm(slug: resource.slug, domainID: resource.domainID)
        checkoutURL = resource.destination ?? ""
        settings = resource.paymentLink
        gate = GateForm(gate: resource.gate)
    }

    /// The checkout as it will be sent: `https://` added to a bare domain,
    /// and only `https` accepted, because a checkout must be secure.
    var normalizedCheckout: URL? {
        guard let url = Destination.normalized(checkoutURL), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    func validate() -> [ResourceField: String] {
        var errors: [ResourceField: String] = [:]
        address.validate(into: &errors)
        if checkoutURL.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.checkout] = String(localized: "A checkout URL is required.")
        } else if normalizedCheckout == nil {
            errors[.checkout] = String(localized: "Enter a secure checkout address starting with https://.")
        }
        gate.validate(into: &errors)
        return errors
    }

    var draft: PaymentLinkDraft {
        PaymentLinkDraft(slug: address.trimmedSlug, domainID: address.domainID,
                         checkoutURL: normalizedCheckout?.absoluteString ?? checkoutURL,
                         settings: settings, gate: gate.gate, password: gate.password)
    }
}

/// A payment link: a short address that sends buyers to a checkout hosted
/// elsewhere. Cardsite takes no payment and sees none; the editor says so.
struct PaymentLinkEditorView: View {
    @State private var model: ResourceEditorModel<PaymentLinkForm>
    let list: ResourceListModel
    let onCreated: (ResourceItem) -> Void

    init(item: ResourceItem?, list: ResourceListModel, onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.list = list
        self.onCreated = onCreated
        _model = State(initialValue: ResourceEditorModel(
            item: item,
            blank: PaymentLinkForm(),
            list: list,
            makeForm: { item in item.link.map(PaymentLinkForm.init(resource:)) ?? PaymentLinkForm() },
            validate: { $0.validate() },
            submit: { [client = list.client] form, item in
                if let item {
                    return .link(try await client.updatePaymentLink(id: item.id, form.draft))
                }
                return .link(try await client.createPaymentLink(form.draft))
            }
        ))
    }

    var body: some View {
        @Bindable var model = model
        ResourceEditorScaffold(kind: .paymentLink, model: model, list: list, onCreated: onCreated) { _ in
            EmptyView()
        } fields: {
            Section {
                ResourceNote(
                    systemImage: "info.circle",
                    message: String(localized: "Cardsite doesn’t process this payment. The address only sends buyers to your checkout; the payment is taken there, by your payment provider.")
                )
            }
            .editorRowBackground()

            Section {
                ResourceAddressRows(kind: .paymentLink, address: $model.form.address, list: list, isNew: model.isNew,
                                    savedAddress: model.savedForm.address, error: model.errors[.slug],
                                    prompt: String(localized: "buy-now"))
                EditorTextField(
                    String(localized: "Checkout URL"),
                    text: $model.form.checkoutURL,
                    prompt: "https://buy.example.com/checkout",
                    kind: .url,
                    help: String(localized: "Visitors are redirected to this checkout page. Paste the payment URL from your payment provider."),
                    error: model.errors[.checkout]
                )
            } header: {
                EditorSectionHeader(String(localized: "Address & checkout"))
            } footer: {
                ResourceAddressFooter(list: list, isNew: model.isNew)
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
}

#Preview("Edit payment link") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.paymentLink, items: [.link(.previewPaymentLink)], client: app.client)
    NavigationStack {
        PaymentLinkEditorView(item: .link(.previewPaymentLink), list: list)
    }
    .environment(app)
}

#Preview("New payment link") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.paymentLink, items: [], client: app.client)
    NavigationStack {
        PaymentLinkEditorView(item: nil, list: list)
    }
    .environment(app)
}
