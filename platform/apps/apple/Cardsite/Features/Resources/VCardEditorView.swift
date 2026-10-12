import SwiftUI
import UniformTypeIdentifiers
import StudioKit
import CardsiteKit

/// Everything the vCard editor edits, as one value.
struct VCardForm: Equatable {
    var address: AddressForm
    var card: VCardSettings
    var gate: GateForm

    init() {
        address = AddressForm()
        card = VCardSettings(phoneNumbers: [VCardEntry()])
        gate = GateForm()
    }

    init(resource: ManagedResource) {
        address = AddressForm(slug: resource.slug, domainID: resource.domainID)
        card = resource.vcard
        gate = GateForm(gate: resource.gate)
    }

    func validate() -> [ResourceField: String] {
        var errors: [ResourceField: String] = [:]
        address.validate(into: &errors)
        if card.firstName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.name] = String(localized: "A first name is required.")
        }
        let email = card.email.trimmingCharacters(in: .whitespaces)
        if !email.isEmpty, !Self.looksLikeEmail(email) {
            errors[.email] = String(localized: "Enter an email address like name@example.com.")
        }
        let website = card.website.trimmingCharacters(in: .whitespaces)
        if !website.isEmpty, Destination.normalized(website) == nil {
            errors[.website] = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
        }
        gate.validate(into: &errors)
        return errors
    }

    var draft: VCardDraft {
        var card = self.card
        let website = card.website.trimmingCharacters(in: .whitespaces)
        if !website.isEmpty { card.website = Destination.normalized(website)?.absoluteString ?? website }
        return VCardDraft(slug: address.trimmedSlug, domainID: address.domainID, card: card,
                          gate: gate.gate, password: gate.password)
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !value.contains(" ")
    }
}

/// A vCard: a live card preview, the contact fields the web edits plus the
/// rest the API stores (website, address, birthday, note, socials), and the
/// gate. Saved cards also offer Add to Contacts (iOS), the `.vcf` and Share.
struct VCardEditorView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ResourceEditorModel<VCardForm>
    let list: ResourceListModel
    let onCreated: (ResourceItem) -> Void

    @State private var isAddingContact = false
    @State private var isExporting = false
    @State private var exportError: String? = nil

    init(item: ResourceItem?, list: ResourceListModel, onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.list = list
        self.onCreated = onCreated
        _model = State(initialValue: ResourceEditorModel(
            item: item,
            blank: VCardForm(),
            list: list,
            makeForm: { item in item.link.map(VCardForm.init(resource:)) ?? VCardForm() },
            validate: { $0.validate() },
            submit: { [client = list.client] form, item in
                if let item {
                    return .link(try await client.updateVCard(id: item.id, form.draft))
                }
                return .link(try await client.createVCard(form.draft))
            }
        ))
    }

    var body: some View {
        @Bindable var model = model
        ResourceEditorScaffold(kind: .vcard, model: model, list: list, onCreated: onCreated) { item in
            if let resource = item.link {
                actions(for: resource)
            }
        } fields: {
            previewSection
            addressSection($model.form)
            contactSection($model.form)
            workSection($model.form)
            postalSection($model.form)
            socialsSection($model.form)
            moreSection($model.form)
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
        #if os(iOS)
        .sheet(isPresented: $isAddingContact) {
            NewContactView(contact: ContactBuilder.contact(from: model.savedForm.card)) {
                isAddingContact = false
            }
            .ignoresSafeArea()
        }
        #endif
        .fileExporter(isPresented: $isExporting, item: exportFile, contentTypes: [.vCard],
                      defaultFilename: exportFile?.filename) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Couldn’t export the card", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var exportFile: RemoteVCardFile? {
        guard let resource = model.item?.link else { return nil }
        return RemoteVCardFile(client: list.client, id: resource.id, name: resource.vcard.fullName)
    }

    @ViewBuilder
    private func actions(for resource: ManagedResource) -> some View {
        #if os(iOS)
        Button {
            isAddingContact = true
        } label: {
            Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
        }
        .buttonStyle(StudioButtonStyle(.outline))
        #else
        ShareLink(item: RemoteVCardFile(client: list.client, id: resource.id, name: resource.vcard.fullName),
                  preview: SharePreview(resource.vcard.fullName.isEmpty ? String(localized: "Contact") : resource.vcard.fullName)) {
            Label("Share .vcf", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(StudioButtonStyle(.outline))
        #endif
        Button {
            isExporting = true
        } label: {
            Label("Download .vcf", systemImage: "arrow.down.doc")
        }
        .buttonStyle(StudioButtonStyle(.outline))
    }

    // MARK: Sections

    private var previewSection: some View {
        Section {
            VCardPreviewCard(card: model.form.card,
                             address: AddressField.liveURL(slug: model.form.address.slug, domainID: model.form.address.domainID,
                                                           domains: list.options.domains, defaultHost: app.addresses.publicHost))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            EditorSectionHeader(String(localized: "Card"))
        }
    }

    private func addressSection(_ form: Binding<VCardForm>) -> some View {
        Section {
            ResourceAddressRows(kind: .vcard, address: form.address, list: list, isNew: model.isNew,
                                savedAddress: model.savedForm.address, error: model.errors[.slug],
                                prompt: String(localized: "my-contact-card"))
        } header: {
            EditorSectionHeader(String(localized: "Address"))
        } footer: {
            ResourceAddressFooter(list: list, isNew: model.isNew)
        }
        .studioRowBackground()
    }

    private func contactSection(_ form: Binding<VCardForm>) -> some View {
        Section {
            EditorTextField(String(localized: "First Name"), text: form.card.firstName, prompt: "Ada",
                            error: model.errors[.name])
                #if os(iOS) || os(visionOS)
                .textContentType(.givenName)
                #endif
            EditorTextField(String(localized: "Last Name"), text: form.card.lastName, prompt: "Lovelace")
                #if os(iOS) || os(visionOS)
                .textContentType(.familyName)
                #endif
            EditorTextField(String(localized: "Email"), text: form.card.email, prompt: "ada@example.com", kind: .plain,
                            error: model.errors[.email])
                #if os(iOS) || os(visionOS)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                #endif
            VCardEntryRows(entries: form.card.phoneNumbers, kind: .phone)
        } header: {
            EditorSectionHeader(String(localized: "Contact"))
        }
        .studioRowBackground()
    }

    private func workSection(_ form: Binding<VCardForm>) -> some View {
        Section {
            EditorTextField(String(localized: "Company"), text: form.card.company, prompt: "Analytical Engines")
                #if os(iOS) || os(visionOS)
                .textContentType(.organizationName)
                #endif
            EditorTextField(String(localized: "Job Title"), text: form.card.jobTitle, prompt: String(localized: "Analyst"))
                #if os(iOS) || os(visionOS)
                .textContentType(.jobTitle)
                #endif
            EditorTextField(String(localized: "Website"), text: form.card.website, prompt: "https://example.com",
                            kind: .url, error: model.errors[.website])
        } header: {
            EditorSectionHeader(String(localized: "Work"))
        }
        .studioRowBackground()
    }

    private func postalSection(_ form: Binding<VCardForm>) -> some View {
        Section {
            EditorTextField(String(localized: "Street"), text: form.card.street, prompt: String(localized: "12 St James’s Square"))
                #if os(iOS) || os(visionOS)
                .textContentType(.fullStreetAddress)
                #endif
            EditorTextField(String(localized: "City"), text: form.card.city, prompt: String(localized: "London"))
                #if os(iOS) || os(visionOS)
                .textContentType(.addressCity)
                #endif
            EditorTextField(String(localized: "Region"), text: form.card.region, prompt: String(localized: "Greater London"))
                #if os(iOS) || os(visionOS)
                .textContentType(.addressState)
                #endif
            EditorTextField(String(localized: "Postcode"), text: form.card.zip, prompt: "SW1Y 4LE", kind: .plain)
                #if os(iOS) || os(visionOS)
                .textContentType(.postalCode)
                #endif
            EditorTextField(String(localized: "Country"), text: form.card.country, prompt: String(localized: "United Kingdom"))
                #if os(iOS) || os(visionOS)
                .textContentType(.countryName)
                #endif
        } header: {
            EditorSectionHeader(String(localized: "Postal address"))
        }
        .studioRowBackground()
    }

    private func socialsSection(_ form: Binding<VCardForm>) -> some View {
        Section {
            VCardEntryRows(entries: form.card.socials, kind: .social)
        } header: {
            EditorSectionHeader(String(localized: "Socials"))
        } footer: {
            Text("A profile or page per row, such as LinkedIn or your portfolio.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .studioRowBackground()
    }

    private func moreSection(_ form: Binding<VCardForm>) -> some View {
        Section {
            Toggle(isOn: birthdayIsSet(form)) {
                Text("Birthday")
            }
            .toggleStyle(.switch)
            if !form.wrappedValue.card.birthday.isEmpty {
                DatePicker(selection: birthday(form), in: ...Date.now, displayedComponents: .date) {
                    Text("Date of birth")
                }
                .environment(\.timeZone, VCardBirthday.zone)
            }
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text("Note")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                    .accessibilityHidden(true)
                TextField(String(localized: "Note"), text: form.card.note,
                          prompt: Text("Anything else people should know"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...6)
                    .studioText(.ui)
            }
            .padding(.vertical, StudioSpace.s1)
        } header: {
            EditorSectionHeader(String(localized: "More"))
        }
        .studioRowBackground()
    }

    private func birthdayIsSet(_ form: Binding<VCardForm>) -> Binding<Bool> {
        Binding(
            get: { !form.wrappedValue.card.birthday.isEmpty },
            set: { isOn in
                form.wrappedValue.card.birthday = isOn ? VCardBirthday.string(from: VCardBirthday.defaultDate) : ""
            }
        )
    }

    private func birthday(_ form: Binding<VCardForm>) -> Binding<Date> {
        Binding(
            get: { VCardBirthday.date(from: form.wrappedValue.card.birthday) ?? VCardBirthday.defaultDate },
            set: { form.wrappedValue.card.birthday = VCardBirthday.string(from: $0) }
        )
    }
}

/// `vcard_birthday` is a calendar date, `YYYY-MM-DD`, with no zone: it is
/// read and written in UTC so it never shifts a day.
enum VCardBirthday {
    static let zone = TimeZone(identifier: "UTC") ?? .gmt

    static var defaultDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    }

    static func date(from value: String) -> Date? {
        CardsiteJSON.parseDay(value.trimmingCharacters(in: .whitespaces), in: zone)
    }

    static func string(from date: Date) -> String {
        CardsiteJSON.dayString(date)
    }
}

// MARK: - Phone numbers and socials

/// An editable list of `{label?, value}` rows with add and remove.
struct VCardEntryRows: View {
    enum Kind {
        case phone, social
    }

    @Binding var entries: [VCardEntry]
    let kind: Kind

    var body: some View {
        ForEach($entries) { $entry in
            HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s2) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    if kind == .social {
                        TextField(String(localized: "Label"), text: $entry.label, prompt: Text("LinkedIn"))
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText2)
                    }
                    valueField($entry)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                }
                Spacer(minLength: StudioSpace.s1)
                Button {
                    entries.removeAll { $0.id == entry.id }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.studioError)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(kind == .phone ? Text("Remove phone number") : Text("Remove profile"))
            }
            .padding(.vertical, StudioSpace.s1)
        }
        .onDelete { entries.remove(atOffsets: $0) }

        Button {
            entries.append(VCardEntry())
        } label: {
            Label(kind == .phone ? String(localized: "Add phone number") : String(localized: "Add profile"),
                  systemImage: "plus.circle")
        }
    }

    @ViewBuilder
    private func valueField(_ entry: Binding<VCardEntry>) -> some View {
        switch kind {
        case .phone:
            TextField(String(localized: "Phone"), text: entry.value, prompt: Text("+44 20 7946 0000"))
                #if os(iOS) || os(visionOS)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                #endif
        case .social:
            TextField(String(localized: "Address"), text: entry.value, prompt: Text("https://linkedin.com/in/ada"))
                .plainEntry()
                #if os(iOS) || os(visionOS)
                .keyboardType(.URL)
                #endif
        }
    }
}

// MARK: - Preview card

/// The card as visitors save it, drawn from Studio surfaces.
struct VCardPreviewCard: View {
    let card: VCardSettings
    let address: URL?

    var body: some View {
        StudioCard {
            if card.fullName.isEmpty {
                Text("Add a name to see the card.")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, StudioSpace.s4)
            } else {
                VStack(alignment: .leading, spacing: StudioSpace.s4) {
                    HStack(alignment: .center, spacing: StudioSpace.s3) {
                        Text(verbatim: initials)
                            .studioText(.titleSm)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(Color.studioAccentInk)
                            .frame(width: StudioSpace.s12, height: StudioSpace.s12)
                            .background(Color.studioAccent, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: StudioSpace.s1) {
                            Text(verbatim: card.fullName)
                                .studioText(.titleSm)
                                .foregroundStyle(Color.studioText)
                                .fixedSize(horizontal: false, vertical: true)
                            if !role.isEmpty {
                                Text(verbatim: role)
                                    .studioText(.uiSm)
                                    .foregroundStyle(Color.studioText2)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        ForEach(card.phoneNumbers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }) { phone in
                            line(phone.value, systemImage: "phone")
                        }
                        if !card.email.isEmpty { line(card.email, systemImage: "envelope") }
                        if !card.website.isEmpty { line(card.website, systemImage: "globe") }
                        if !postal.isEmpty { line(postal, systemImage: "mappin.and.ellipse") }
                        ForEach(card.socials.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }) { social in
                            line(social.label.isEmpty ? social.value : "\(social.label) · \(social.value)", systemImage: "link")
                        }
                    }
                    if let address {
                        Divider()
                        Label {
                            Text(verbatim: address.host().map { "\($0)\(address.path())" } ?? address.absoluteString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "qrcode")
                        }
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Card preview"))
    }

    private var initials: String {
        let letters = [card.firstName, card.lastName].compactMap { $0.trimmingCharacters(in: .whitespaces).first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var role: String {
        [card.jobTitle, card.company].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var postal: String {
        [card.street, card.city, card.region, card.zip, card.country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func line(_ text: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.studioAccentLine)
        }
        .studioText(.ui)
        .foregroundStyle(Color.studioText)
    }
}

#Preview("Edit vCard") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.vcard, items: [.link(.previewVCard)], client: app.client)
    NavigationStack {
        VCardEditorView(item: .link(.previewVCard), list: list)
    }
    .environment(app)
}

#Preview("New vCard") {
    let app = AppModel(configuration: .preview)
    let list = ResourceListModel.preview(.vcard, items: [], client: app.client)
    NavigationStack {
        VCardEditorView(item: nil, list: list)
    }
    .environment(app)
}
