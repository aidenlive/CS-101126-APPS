import SwiftUI
import StudioKit
import CardsiteKit

// The domain editor: the form sections shared by "Add domain" and a
// domain's own page, the page itself (status, verify, DNS, settings,
// delete), and the add sheet.

// MARK: - Form sections

/// Scheme and host, type and redirect, the two custom pages, and the three
/// switches: every field the web's domain drawer has, with its labels.
struct DomainFormSections: View {
    @Binding var input: CustomDomainInput
    var hostError: String?

    private var forceSSL: Binding<Bool> {
        Binding(get: { input.sslIsEnabled && input.forceSSL }, set: { input.forceSSL = $0 })
    }

    var body: some View {
        Section {
            Picker("Scheme", selection: $input.scheme) {
                Text(verbatim: "https://").tag("https")
                Text(verbatim: "http://").tag("http")
            }
            EditorTextField(String(localized: "Host"), text: $input.host, prompt: "example.com",
                            kind: .plain, error: hostError)
                .accessibilityIdentifier("org.domains.editor.host")
        } header: {
            EditorSectionHeader(String(localized: "Address"))
        }
        .editorRowBackground()

        Section {
            Picker("Domain type", selection: $input.kind) {
                ForEach(DomainKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            Picker("Redirect type", selection: $input.redirectType) {
                ForEach(DomainRedirectType.allCases) { redirect in
                    Text(redirect.title).tag(redirect)
                }
            }
        } header: {
            EditorSectionHeader(String(localized: "Behaviour"))
        }
        .editorRowBackground()

        Section {
            EditorTextField(String(localized: "Custom index URL"), text: $input.customIndexURL,
                            prompt: "https://example.com", kind: .url)
            EditorTextField(String(localized: "Custom 404 URL"), text: $input.customNotFoundURL,
                            prompt: "https://example.com/404", kind: .url)
        } header: {
            EditorSectionHeader(String(localized: "Pages"))
        }
        .editorRowBackground()

        Section {
            Toggle("SSL enabled", isOn: $input.sslIsEnabled.animation(StudioAnimation.base))
            // Redirecting to HTTPS means nothing without SSL, so the switch
            // reads off and can't be turned on until SSL is.
            Toggle(isOn: forceSSL) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Force SSL (redirect HTTP → HTTPS)")
                    if !input.sslIsEnabled {
                        Text("Requires SSL enabled")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
            }
            .disabled(!input.sslIsEnabled)
            Toggle("Forward query parameters", isOn: $input.forwardParameters)
        } header: {
            EditorSectionHeader(String(localized: "Options"))
        }
        .editorRowBackground()
    }
}

// MARK: - DNS

/// What to do at the DNS provider. The server checks for a CNAME to this
/// deployment, or, for an apex domain, A/AAAA records matching its
/// addresses (services/domain_verification.go). Its 422 names the exact
/// target, which the verify banner shows.
struct DomainDNSInstructions: View {
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                Text(verbatim: host.isEmpty ? "—" : host)
                    .studioText(.mono)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: StudioSpace.s2)
                if !host.isEmpty {
                    Button {
                        Pasteboard.copy(host)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Copy host"))
                }
            }
            Text("Add a CNAME record for this host that points at this Cardsite deployment. An apex domain (one without a subdomain) can't carry a CNAME: give it A and AAAA records with the deployment's addresses instead.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Then verify. If the host doesn't point here yet, verification names the exact target. DNS changes can take a while to propagate.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, StudioSpace.s1)
    }
}

/// The last verification answer, with the server's own words.
struct DomainCheckBanner: View {
    let check: DomainsModel.Check
    let host: String
    let dismiss: () -> Void

    var body: some View {
        StudioBanner(
            lead: DomainCheckCopy.title(for: check, host: host),
            message: DomainCheckCopy.message(for: check),
            tone: DomainCheckCopy.tone(for: check),
            onDismiss: dismiss
        )
        .accessibilityIdentifier("org.domains.verify.result")
    }
}

// MARK: - A domain's page

/// Status and verification first, then what to set at the DNS provider,
/// then the editable settings (Save in the toolbar), then delete.
struct DomainDetailView: View {
    let model: DomainsModel

    @Environment(\.dismiss) private var dismiss
    /// The domain as last saved or verified.
    @State private var domain: CustomDomain
    @State private var draft: CustomDomainInput
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var hostError: String? = nil
    @State private var pendingDelete: CustomDomain? = nil

    init(model: DomainsModel, domain: CustomDomain) {
        self.model = model
        _domain = State(initialValue: domain)
        _draft = State(initialValue: CustomDomainInput(domain))
    }

    private var isDirty: Bool { draft != CustomDomainInput(domain) }
    private var isVerifying: Bool { model.verifying.contains(domain.id) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Verification") {
                    StudioStatusPill(domain.isVerified ? String(localized: "Verified") : String(localized: "Unverified"),
                                     tone: domain.isVerified ? .success : .neutral)
                }
                LabeledContent("Status") {
                    StudioStatusPill(domain.isEnabled ? String(localized: "Active") : String(localized: "Inactive"),
                                     tone: domain.isEnabled ? .success : .neutral)
                }
                if let checked = domain.lastVerifiedAt {
                    LabeledContent("Last checked") {
                        Text(checked.formatted(.relative(presentation: .named)))
                    }
                }
                if let check = model.checks[domain.id] {
                    DomainCheckBanner(check: check, host: domain.host) { model.dismissCheck(for: domain.id) }
                        .listRowInsets(EdgeInsets(top: StudioSpace.s2, leading: StudioSpace.s2,
                                                  bottom: StudioSpace.s2, trailing: StudioSpace.s2))
                }
                Button {
                    Task { await verify() }
                } label: {
                    HStack(spacing: StudioSpace.s2) {
                        if isVerifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text(domain.isVerified ? String(localized: "Verify Again") : String(localized: "Verify Domain"))
                    }
                }
                .disabled(isVerifying || isDirty)
                .accessibilityIdentifier("org.domains.verify")
            } header: {
                EditorSectionHeader(String(localized: "Status"))
            } footer: {
                if isDirty {
                    Text("Save your changes before verifying.")
                }
            }
            .editorRowBackground()

            Section {
                DomainDNSInstructions(host: domain.host)
            } header: {
                EditorSectionHeader(String(localized: "DNS"))
            }
            .editorRowBackground()

            DomainFormSections(input: $draft, hostError: hostError)

            Section {
                Button("Delete Domain…", role: .destructive) { pendingDelete = domain }
                    .accessibilityIdentifier("org.domains.delete")
            } footer: {
                FormErrorText(message: saveError)
            }
            .editorRowBackground()
        }
        .resourceEditorForm()
        .navigationTitle(domain.host)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .unsavedChanges(isDirty: isDirty, isSaving: isSaving, save: { await save() }, discard: {
            draft = CustomDomainInput(domain)
            hostError = nil
            saveError = nil
        })
        .onChange(of: draft.host) { _, _ in hostError = nil }
        .organiseDeleteFlow(
            $pendingDelete,
            title: String(localized: "Delete this domain?"),
            confirmTitle: { String(localized: "Delete \($0.host)") },
            message: String(localized: "Are you sure you want to delete this domain? This can't be undone."),
            delete: { [model] domain in
                try await model.delete(domain)
                dismiss()
            }
        )
    }

    private func save() async -> Bool {
        guard draft.hasValidHost else {
            hostError = String(localized: "Enter a host such as links.example.com.")
            return false
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let saved = try await model.update(domain, to: draft)
            domain = saved
            draft = CustomDomainInput(saved)
            Haptics.success()
            return true
        } catch {
            saveError = error.asAPIError.localizedDescription
            return false
        }
    }

    private func verify() async {
        if let fresh = await model.verify(domain) {
            domain = fresh
            if !isDirty { draft = CustomDomainInput(fresh) }
        }
        if model.checks[domain.id] == .verified { Haptics.success() }
    }
}

// MARK: - Add

/// The web's "Add domain" drawer. Once the domain exists, the sheet turns
/// into the DNS step: what to set, and Verify.
struct DomainCreateSheet: View {
    let model: DomainsModel

    @Environment(\.dismiss) private var dismiss
    @State private var input = CustomDomainInput()
    @State private var hostError: String? = nil
    @State private var error: String? = nil
    @State private var isSaving = false
    @State private var created: CustomDomain? = nil

    private var isDirty: Bool { input != CustomDomainInput() }
    private var canSave: Bool { !input.normalizedHost.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    createdForm(created)
                } else {
                    Form {
                        Section {
                        } footer: {
                            Text("Where your links are served from, and how that host behaves.")
                        }
                        DomainFormSections(input: $input, hostError: hostError)
                        if let error {
                            Section {
                            } footer: {
                                FormErrorText(message: error)
                            }
                        }
                    }
                    .resourceEditorForm()
                    .onChange(of: input.host) { _, _ in hostError = nil }
                }
            }
            .navigationTitle(created == nil ? String(localized: "Add domain") : (created?.host ?? ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if created != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                                .accessibilityLabel(Text("Saving"))
                        } else {
                            Button("Add") { Task { await save() } }
                                .disabled(!canSave)
                                .keyboardShortcut("s", modifiers: .command)
                                .accessibilityIdentifier("org.domains.editor.save")
                        }
                    }
                }
            }
            .interactiveDismissDisabled(created == nil && (isDirty || isSaving))
        }
        .organiseSheetFrame()
    }

    private func createdForm(_ domain: CustomDomain) -> some View {
        let current = model.list.items.first { $0.id == domain.id } ?? domain
        let verifying = model.verifying.contains(domain.id)
        return Form {
            Section {
                StudioBanner(lead: String(localized: "Domain added."),
                             message: String(localized: "Point it at Cardsite, then verify it to start serving links."),
                             tone: .success)
                    .listRowInsets(EdgeInsets(top: StudioSpace.s2, leading: StudioSpace.s2,
                                              bottom: StudioSpace.s2, trailing: StudioSpace.s2))
            }
            .editorRowBackground()

            Section {
                DomainDNSInstructions(host: current.host)
            } header: {
                EditorSectionHeader(String(localized: "DNS"))
            }
            .editorRowBackground()

            Section {
                if let check = model.checks[domain.id] {
                    DomainCheckBanner(check: check, host: current.host) { model.dismissCheck(for: domain.id) }
                        .listRowInsets(EdgeInsets(top: StudioSpace.s2, leading: StudioSpace.s2,
                                                  bottom: StudioSpace.s2, trailing: StudioSpace.s2))
                }
                Button {
                    Task {
                        await model.verify(current)
                        if model.checks[domain.id] == .verified { Haptics.success() }
                    }
                } label: {
                    HStack(spacing: StudioSpace.s2) {
                        if verifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text(current.isVerified ? String(localized: "Verified") : String(localized: "Verify Domain"))
                    }
                }
                .disabled(verifying || current.isVerified)
                .accessibilityIdentifier("org.domains.verify")
            } footer: {
                Text("You can also verify later from the domain's page.")
            }
            .editorRowBackground()
        }
        .resourceEditorForm()
    }

    private func save() async {
        guard input.hasValidHost else {
            hostError = String(localized: "Enter a host such as links.example.com.")
            return
        }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            created = try await model.create(input)
            Haptics.success()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Domain, verified") {
    let model = DomainsModel(client: OrganisePreviewData.client)
    model.seed(OrganisePreviewData.domains)
    return NavigationStack { DomainDetailView(model: model, domain: OrganisePreviewData.domains[1]) }
        .environment(AppModel.preview())
}

#Preview("Domain, pending DNS") {
    let model = DomainsModel(client: OrganisePreviewData.client)
    let pending = OrganisePreviewData.domains[0]
    model.seed(OrganisePreviewData.domains, checks: [
        pending.id: .pending(title: "\(pending.host) does not point at this deployment yet",
                             message: "Point \(pending.host) at card.site, then verify again. DNS changes can take a while to propagate."),
    ])
    return NavigationStack { DomainDetailView(model: model, domain: pending) }
        .environment(AppModel.preview())
}

#Preview("Add domain") {
    DomainCreateSheet(model: DomainsModel(client: OrganisePreviewData.client))
}
#endif
