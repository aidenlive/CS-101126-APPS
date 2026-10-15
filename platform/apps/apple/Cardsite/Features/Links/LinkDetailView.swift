import SwiftUI
import StudioKit
import CardsiteKit

/// A short link: its status and traffic at the top, then every setting the
/// web's link page has, in the same sections (LinkDetailPage.tsx): address
/// and destination, schedule and targeting, gating, cloaking and UTM,
/// advanced, and the danger zone.
///
/// The page is the calm-form editor (DESIGN-DIRECTION "Editors"): a hero
/// with the address in display type, where it leads, its state, figures
/// and Copy Link / Open / Card; then the grouped form. The bar carries the
/// title `/slug` with the host under it, one … menu of secondary actions,
/// and ✓ only while there is something to save.
///
/// Edits are held until Save (✓, ⌘S). Leaving with changes asks first.
/// The enabled switch, delete and the header actions act at once.
struct LinkDetailView: View {
    @Environment(LinksModel.self) private var links
    @State private var loadedModel: LinkDetailModel? = nil

    let link: Resource
    var onDeleted: () -> Void
    /// After Duplicate: the copy, for a list that can select it.
    var onDuplicated: (Resource) -> Void
    private var suppliedModel: LinkDetailModel?

    init(link: Resource, onDeleted: @escaping () -> Void = {}, onDuplicated: @escaping (Resource) -> Void = { _ in }) {
        self.link = link
        self.onDeleted = onDeleted
        self.onDuplicated = onDuplicated
    }

    /// Preview seam: a model already holding a link.
    init(model: LinkDetailModel) {
        self.link = model.seed
        self.onDeleted = {}
        self.onDuplicated = { _ in }
        self.suppliedModel = model
    }

    private var model: LinkDetailModel? { suppliedModel ?? loadedModel }

    var body: some View {
        Group {
            if let model {
                LinkDetailForm(model: model, options: links.options, onDeleted: onDeleted, onDuplicated: onDuplicated)
            } else {
                // The model exists one frame later (`.task`): an empty page
                // rather than a spinner that flashes.
                Color.studioBg
                    .accessibilityElement()
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
    @Environment(LinksModel.self) private var links
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.toasts) private var toasts
    @Bindable var model: LinkDetailModel
    let options: ResourceOptionsModel
    let onDeleted: () -> Void
    let onDuplicated: (Resource) -> Void

    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    @State private var isDuplicating = false
    @State private var duplicateError: String? = nil
    @State private var showsStatistics = false

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
        .editorSubtitle(publicURL?.host() ?? app.addresses.publicHost)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .editorMoreMenu { moreMenu }
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
        .navigationDestination(isPresented: $showsStatistics) {
            StatisticsScreen(route: statisticsRoute)
        }
        .task { [model] in await model.load() }
        .task { [options] in await options.loadIfNeeded() }
        .onChange(of: model.form) { old, new in model.formChanged(from: old, to: new) }
        .confirmationDialog(
            ResourceKind.shortLinkDeleteConfirmation,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text(ResourceKind.shortLinkDeleteConsequence)
        }
        .alert("Couldn’t delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn’t duplicate", isPresented: Binding(get: { duplicateError != nil }, set: { if !$0 { duplicateError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateError ?? "")
        }
    }

    // MARK: More menu

    /// The secondary actions, in the standard order (ResourceMenuItems):
    /// share and card; statistics, QR code and duplicate; delete.
    @ViewBuilder
    private var moreMenu: some View {
        if let url = publicURL {
            ShareLink(item: url) { ResourceVerb.share.label }
        }
        if let card = app.addresses.cardURL(for: model.slug) {
            Button { openURL(card) } label: { ResourceVerb.showCard.label }
        }
        Divider()
        Button { showsStatistics = true } label: { ResourceVerb.statistics.label }
        if let url = publicURL {
            Button { app.composeQRCode(for: url) } label: { Label("Create QR Code", systemImage: "qrcode") }
        }
        Button { Task { await duplicate() } } label: { ResourceVerb.duplicate.label }
            .disabled(isDuplicating || model.detail == nil)
        Divider()
        Button(role: .destructive) { isConfirmingDelete = true } label: { ResourceVerb.delete.label }
            .disabled(isDeleting)
    }

    private var statisticsRoute: StatisticsRoute {
        StatisticsRoute(linkID: model.linkID, subtitle: displayAddress)
    }

    private func duplicate() async {
        guard !isDuplicating else { return }
        isDuplicating = true
        defer { isDuplicating = false }
        do {
            let copy = try await links.duplicate(model.seed)
            Haptics.success()
            toasts?.show(String(localized: "Duplicated as /\(copy.slug). The copy starts switched off."), variant: .success)
            onDuplicated(copy)
        } catch {
            duplicateError = error.asAPIError.localizedDescription
        }
    }

    private var form: some View {
        Form {
            header
            if let error = model.refreshError {
                Section {
                    RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                }
                .studioClearRow()
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
                .studioRowBackground()
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
        ResourceHeaderSection(
            state: ResourceState(isEnabled: model.isEnabled, isLapsing: model.isLapsing),
            didJustSave: model.didJustSave,
            title: displayAddress,
            subtitle: destinationSummary,
            url: publicURL,
            cardURL: app.addresses.cardURL(for: model.slug),
            cardHint: String(localized: "Opens the summary card at \(app.addresses.display(for: "@" + model.slug))"),
            toggle: ResourceLiveToggle(
                isOn: model.isEnabled,
                isBusy: model.isTogglingEnabled || model.detail == nil,
                error: model.toggleError,
                identifier: "link.detail.enabled",
                set: { [model] isOn in Task { await model.setEnabled(isOn) } }
            ),
            figures: [
                ResourceFigure(title: String(localized: "Clicks · 30d"), value: model.recent?.pageviews),
                ResourceFigure(title: String(localized: "Visitors · 30d"), value: model.recent?.visitors),
                ResourceFigure(title: String(localized: "All time"), value: model.clicks),
            ],
            isLapsing: model.isLapsing
        ) {
            EmptyView()
        } rows: {
            NavigationLink(value: statisticsRoute) {
                ResourceVerb.statistics.label
            }
            if let url = publicURL {
                Button {
                    app.composeQRCode(for: url)
                } label: {
                    Label("Create QR Code", systemImage: "qrcode")
                }
                .accessibilityIdentifier("link.detail.qr")
            }
        }
    }

    /// The destination as host and path ("example.com/menu"); the field
    /// below has the whole address.
    private var destinationSummary: String? {
        let saved = model.savedForm?.destination ?? model.destination
        return ResourceItem.host(of: saved)
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
            if options.pickersFailed {
                FormRetryRow(message: String(localized: "Domains, projects and splash pages couldn’t be loaded.")) { [options] in
                    await options.load()
                }
            }
        } header: {
            EditorSectionHeader(String(localized: "Address & destination"))
        } footer: {
            if !options.pickersFailed, options.usableDomains().isEmpty {
                Text("Verified custom domains appear here as address options.")
            } else {
                Text("Change the destination any time: the address and its QR codes follow it.")
            }
        }
        .studioRowBackground()

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
            Text("Cloaking shows the destination inside a page at your address. UTM parameters tell the destination’s analytics where visits came from.")
        }
        .studioRowBackground()

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
        } footer: {
            Text("How the redirect behaves, a page shown before it, and the project it’s filed under.")
        }
        .studioRowBackground()

        if let message = model.formError {
            Section {
                FormErrorText(message: message)
            }
            .studioRowBackground()
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
                    ResourceVerb.delete.label
                    Spacer()
                    if isDeleting { ProgressView() }
                }
            }
            .disabled(isDeleting)
        } header: {
            EditorSectionHeader(String(localized: "Danger zone"))
        } footer: {
            Text(ResourceKind.shortLinkDeleteConsequence)
        }
        .studioRowBackground()
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
