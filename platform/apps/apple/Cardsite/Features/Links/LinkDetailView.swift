import SwiftUI
import StudioKit
import CardsiteKit

/// A short link: its status and traffic at the top, then every setting the
/// web's link page has, in the same sections (LinkDetailPage.tsx): address
/// and destination, schedule and targeting, gating, cloaking and UTM,
/// advanced, and the danger zone.
///
/// Edits are held until Save (toolbar, ⌘S). Leaving with changes asks first.
/// The enabled switch, delete and the header actions act at once.
struct LinkDetailView: View {
    @Environment(LinksModel.self) private var links
    @State private var loadedModel: LinkDetailModel? = nil

    let link: Resource
    var onDeleted: () -> Void
    private var suppliedModel: LinkDetailModel?

    init(link: Resource, onDeleted: @escaping () -> Void = {}) {
        self.link = link
        self.onDeleted = onDeleted
    }

    /// Preview seam: a model already holding a link.
    init(model: LinkDetailModel) {
        self.link = model.seed
        self.onDeleted = {}
        self.suppliedModel = model
    }

    private var model: LinkDetailModel? { suppliedModel ?? loadedModel }

    var body: some View {
        Group {
            if let model {
                LinkDetailForm(model: model, options: links.options, onDeleted: onDeleted)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.studioBg)
                    .accessibilityLabel(Text("Loading"))
            }
        }
        .task {
            if model == nil {
                loadedModel = LinkDetailModel(seed: link, links: links)
            }
        }
    }
}

// MARK: - Form

private struct LinkDetailForm: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LinkDetailModel
    let options: ResourceOptionsModel
    let onDeleted: () -> Void

    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    @State private var copied = false

    var body: some View {
        Group {
            if let error = model.loadError, model.detail == nil {
                ErrorStateView(error: error) { [model] in await model.load() }
                    .background(Color.studioBg)
            } else {
                form
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link.detail")
        .navigationTitle(Text(verbatim: "/" + model.slug))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let url = publicURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .unsavedChanges(
            isDirty: model.isDirty,
            isSaving: model.isSaving,
            save: { [model] in await model.save() },
            discard: { [model] in model.discard() },
            saveIdentifier: "link.detail.save"
        )
        .navigationDestination(for: StatisticsRoute.self) { route in
            StatisticsScreen(route: route)
        }
        .task { [model] in await model.load() }
        .task { [options] in await options.loadIfNeeded() }
        .onChange(of: model.form) { old, new in model.formChanged(from: old, to: new) }
        .confirmationDialog(
            String(localized: "Delete /\(model.slug)?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Its address stops resolving immediately. This cannot be undone.")
        }
        .alert("Couldn’t delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var form: some View {
        Form {
            header
            if let error = model.refreshError {
                Section {
                    RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                }
                .listRowBackground(Color.clear)
            }
            if let current = model.form {
                editor(binding(fallback: current))
            } else {
                Section {
                    HStack(spacing: StudioSpace.s3) {
                        ProgressView()
                        Text("Loading settings…")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .editorRowBackground()
            }
            dangerZone
        }
        .resourceEditorForm()
        .refreshable { [model, options] in
            async let link: Void = model.load()
            async let pickers: Void = options.load()
            _ = await (link, pickers)
        }
        .animation(StudioAnimation.base, value: model.form == nil)
    }

    /// A binding to the form that never reads nil while this view exists.
    private func binding(fallback: LinkForm) -> Binding<LinkForm> {
        Binding(
            get: { model.form ?? fallback },
            set: { model.form = $0 }
        )
    }

    private var publicURL: URL? {
        guard let detail = model.detail else { return app.addresses.url(for: model.slug) }
        return AddressField.liveURL(slug: detail.slug, domainID: detail.domainID,
                                    domains: options.domains, defaultHost: app.addresses.publicHost)
    }

    private var displayAddress: String {
        if let url = publicURL, let host = url.host() {
            return "\(host)\(url.path())"
        }
        return app.addresses.display(for: model.slug)
    }

    // MARK: Header

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                HStack(spacing: StudioSpace.s2) {
                    statusPill
                    if model.didJustSave {
                        StudioStatusPill(String(localized: "Saved"), tone: .success)
                            .transition(.opacity)
                    }
                }
                Text(verbatim: displayAddress)
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                if let destination = model.destination, !destination.isEmpty {
                    Text(verbatim: destination)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s2) { headerActions }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) { headerActions }
                }
                .padding(.top, StudioSpace.s1)
            }
            .padding(.vertical, StudioSpace.s2)

            Toggle(isOn: Binding(
                get: { model.isEnabled },
                set: { newValue in Task { await model.setEnabled(newValue) } }
            )) {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    model.isEnabled ? Text("Active") : Text("Disabled")
                    Text(model.isEnabled
                         ? String(localized: "Resolving")
                         : String(localized: "Returns 404. The address stays yours."))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("link.detail.enabled")
            .disabled(model.isTogglingEnabled || model.detail == nil)
            if let error = model.toggleError {
                FormErrorText(message: error)
            }

            figures

            NavigationLink(value: StatisticsRoute(linkID: model.linkID, subtitle: displayAddress)) {
                Label("Full statistics", systemImage: "chart.bar.xaxis")
            }
            if let url = publicURL {
                Button {
                    app.composeQRCode(for: url)
                } label: {
                    Label("Create QR code", systemImage: "qrcode")
                }
                .accessibilityIdentifier("link.detail.qr")
            }

            if model.isLapsing {
                StudioBanner(
                    lead: String(localized: "This address is in its release window."),
                    message: String(localized: "It may be released to others soon. How addresses are kept: cardsite.com/url-lifecycle."),
                    tone: .warning
                )
            }
        }
        .editorRowBackground()
    }

    @ViewBuilder
    private var statusPill: some View {
        if !model.isEnabled {
            StudioStatusPill(String(localized: "Off"), tone: .neutral)
        } else if model.isLapsing {
            StudioStatusPill(String(localized: "Lapsing"), tone: .warning)
        } else {
            StudioStatusPill(String(localized: "Live"), tone: .success)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        StudioButton(copied ? String(localized: "Copied") : String(localized: "Copy"),
                     systemImage: copied ? "checkmark" : "doc.on.doc",
                     variant: .primary) {
            copy()
        }
        if let url = publicURL {
            Link(destination: url) {
                Label("Open", systemImage: "safari")
            }
            .buttonStyle(.bordered)
        }
        if let card = app.addresses.cardURL(for: model.slug) {
            Link(destination: card) {
                Label("Card View", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Opens the summary card at \(app.addresses.display(for: "@" + model.slug))"))
        }
    }

    private var figures: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: StudioSpace.s4) { figureItems }
            VStack(alignment: .leading, spacing: StudioSpace.s3) { figureItems }
        }
        .padding(.vertical, StudioSpace.s1)
    }

    @ViewBuilder
    private var figureItems: some View {
        HeaderFigure(title: String(localized: "Clicks (30 d)"), value: model.recent?.pageviews)
        HeaderFigure(title: String(localized: "Visitors (30 d)"), value: model.recent?.visitors)
        HeaderFigure(title: String(localized: "All time"), value: model.clicks)
    }

    private func copy() {
        guard let url = publicURL else { return }
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    // MARK: Editor sections

    @ViewBuilder
    private func editor(_ form: Binding<LinkForm>) -> some View {
        let saved = model.savedForm ?? form.wrappedValue

        Section {
            AddressField(
                slug: form.slug,
                domainID: form.domainID,
                domains: options.usableDomains(keeping: form.wrappedValue.domainID),
                defaultHost: app.addresses.publicHost,
                error: model.errors[.slug],
                isSaved: form.wrappedValue.slug == saved.slug && form.wrappedValue.domainID == saved.domainID
            )
            EditorTextField(
                String(localized: "Destination URL"),
                text: form.destination,
                prompt: "https://example.com",
                kind: .url,
                help: String(localized: "The address and any printed QR codes keep working and send people here instead."),
                error: model.errors[.destination]
            )
            .accessibilityIdentifier("link.detail.destination")
            if let archive = model.detail?.archiveURL {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Archive address")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                    Link(destination: archive) {
                        Text(verbatim: archive.absoluteString)
                            .studioText(.ui)
                            .multilineTextAlignment(.leading)
                    }
                    Text("This name was released, so it is free for anyone to claim. Nothing was deleted — what was here stays readable at this address.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, StudioSpace.s1)
            }
        } header: {
            EditorSectionHeader(String(localized: "Address & destination"))
        } footer: {
            if options.pickersFailed {
                Text("Domains, projects and splash pages couldn’t be loaded. Pull to refresh to try again.")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            } else if options.usableDomains().isEmpty {
                Text("Verified custom domains appear here as address options.")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .editorRowBackground()

        ScheduleSection(
            isScheduled: form.isScheduled,
            start: form.start,
            end: form.end,
            timezone: form.timezone,
            canRemove: !form.wrappedValue.hasSavedSchedule,
            error: model.errors[.schedule],
            title: String(localized: "Schedule & targeting")
        )

        DisplayRulesSection(
            rules: form.displayRules,
            options: options.targeting.value,
            loadFailed: options.targeting.error != nil,
            isLocked: !options.allowsTargeting,
            error: model.errors[.targeting]
        )

        GatingSection(
            password: form.password,
            hasPassword: saved.settings.hasPassword,
            clicksLimit: form.clicksLimitText,
            expirationURL: form.settings.expirationURL,
            sensitiveContent: form.settings.sensitiveContent,
            passwordLocked: !options.allowsPasswordProtection,
            errors: .init(password: model.errors[.password],
                          clicksLimit: model.errors[.clicksLimit],
                          expirationURL: model.errors[.expirationURL])
        )

        Section {
            Toggle(isOn: form.settings.cloakingEnabled) {
                Text("Enable link cloaking")
            }
            .toggleStyle(.switch)
            if form.wrappedValue.settings.cloakingEnabled {
                EditorTextField(String(localized: "Cloaking title"), text: form.settings.cloakingTitle,
                                prompt: String(localized: "Page title shown in browser tab"))
                EditorTextField(String(localized: "Meta description"), text: form.settings.cloakingMetaDescription,
                                prompt: String(localized: "Page meta description"))
            }
            EditorTextField(String(localized: "UTM source"), text: form.settings.utmSource, prompt: "google", kind: .plain)
            EditorTextField(String(localized: "UTM medium"), text: form.settings.utmMedium, prompt: "cpc", kind: .plain)
            EditorTextField(String(localized: "UTM campaign"), text: form.settings.utmCampaign, prompt: "spring_sale", kind: .plain)
        } header: {
            EditorSectionHeader(String(localized: "Cloaking & UTM"))
        } footer: {
            Text("Cloaking shows the destination inside a page at your address. UTM parameters are added to the destination so its analytics see where visits came from.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .editorRowBackground()

        Section {
            Picker(selection: form.settings.redirectStatus) {
                ForEach(RedirectStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            } label: {
                Text("HTTP redirect status")
            }
            Toggle(isOn: form.settings.forwardQueryParameters) {
                Text("Forward query parameters to destination")
            }
            .toggleStyle(.switch)
            Picker(selection: form.splashPageID) {
                Text("None").tag(Int?.none)
                ForEach(splashPages(keeping: form.wrappedValue.splashPageID)) { page in
                    Text(verbatim: page.displayName).tag(Int?.some(page.id))
                }
            } label: {
                Text("Splash page")
            }
            Picker(selection: form.projectID) {
                Text("None").tag(Int?.none)
                ForEach(projects(keeping: form.wrappedValue.projectID)) { project in
                    Text(verbatim: project.name).tag(Int?.some(project.id))
                }
            } label: {
                Text("Project")
            }
        } header: {
            EditorSectionHeader(String(localized: "Advanced"))
        }
        .editorRowBackground()

        if let message = model.formError {
            Section {
                FormErrorText(message: message)
            }
            .editorRowBackground()
        }
    }

    /// The picker's list, plus the stored reference if the list doesn't have
    /// it (not loaded yet, or deleted), so a Picker never has a dangling tag.
    private func splashPages(keeping id: Int?) -> [SplashPageOption] {
        var pages = options.splashPages
        if let id, !pages.contains(where: { $0.id == id }) {
            pages.append(SplashPageOption(id: id, name: String(localized: "Splash page #\(id)")))
        }
        return pages
    }

    private func projects(keeping id: Int?) -> [ProjectOption] {
        var projects = options.projects
        if let id, !projects.contains(where: { $0.id == id }) {
            projects.append(ProjectOption(id: id, name: String(localized: "Project #\(id)")))
        }
        return projects
    }

    // MARK: Danger zone

    private var dangerZone: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                HStack {
                    Label("Delete link", systemImage: "trash")
                    Spacer()
                    if isDeleting { ProgressView() }
                }
            }
            .disabled(isDeleting)
        } header: {
            EditorSectionHeader(String(localized: "Danger zone"))
        } footer: {
            Text("The address stops resolving immediately. This cannot be undone.")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .editorRowBackground()
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await model.delete()
            model.discard()
            onDeleted()
            dismiss()
        } catch {
            deleteError = error.asAPIError.localizedDescription
        }
    }
}

/// A figure in the header: label over number, "—" while unknown.
private struct HeaderFigure: View {
    let title: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(Color.studioText3)
            Text(verbatim: value?.grouped ?? "—")
                .studioText(.titleSm)
                .foregroundStyle(Color.studioText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

extension RedirectStatus {
    /// The web's option labels.
    var title: String {
        switch self {
        case .permanent: return String(localized: "301 — Permanent redirect")
        case .temporary: return String(localized: "302 — Temporary redirect")
        case .temporaryPreservingMethod: return String(localized: "307 — Temporary redirect (preserve method)")
        }
    }
}

// MARK: - Previews

extension LinkDetail {
    /// Fixture 22b, the fully configured link.
    static let preview = LinkDetail(
        id: 22, workspaceID: 234, slug: "spring-menu", destination: "https://example.com/full",
        projectID: 3, domainID: nil, splashPageID: 3,
        settings: LinkSettings(clicksLimit: 100, expirationURL: "https://example.com/expired", sensitiveContent: true,
                               cloakingEnabled: true, cloakingTitle: "Cloaked", redirectStatus: .permanent,
                               forwardQueryParameters: true, utmSource: "newsletter", utmMedium: "email",
                               utmCampaign: "launch", hasPassword: true),
        displayRules: DisplayRules([.countries: ["GB", "US"], .deviceTypes: ["mobile"], .languages: ["en"]]),
        timezone: "Europe/London",
        scheduledAt: Date.now.addingTimeInterval(86_400),
        scheduledEnd: Date.now.addingTimeInterval(31 * 86_400),
        clicks: 1_284
    )
}

#Preview("Link detail") {
    let app = AppModel(configuration: .preview)
    let options = ResourceOptionsModel(
        client: app.client, targeting: .preview,
        domains: [DomainOption(id: 3, host: "go.example.com")],
        projects: [ProjectOption(id: 3, name: "Launch week")],
        splashPages: [SplashPageOption(id: 3, name: "Wait")]
    )
    let links = LinksModel(client: app.client, options: options)
    let model = LinkDetailModel(detail: .preview, links: links,
                                recent: .init(pageviews: 412, visitors: 288))
    NavigationStack {
        LinkDetailView(model: model)
    }
    .environment(app)
    .environment(links)
}

#Preview("Plan without targeting") {
    let app = AppModel(configuration: .preview)
    let options = ResourceOptionsModel(
        client: app.client, targeting: .preview,
        capabilities: PlanCapabilities(settings: [:])
    )
    let links = LinksModel(client: app.client, options: options)
    let model = LinkDetailModel(detail: .preview, links: links)
    NavigationStack {
        LinkDetailView(model: model)
    }
    .environment(app)
    .environment(links)
}
