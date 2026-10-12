import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Branded hosts links are served from: list, add, edit, verify, delete.
/// The web's `/domains`.
@MainActor
@Observable
final class DomainsModel {
    /// The last verification answer for a domain, as the screens show it.
    enum Check: Equatable {
        case verified
        /// The server's 422: `title` names the host, `message` says what
        /// to point it at.
        case pending(title: String, message: String?)
        /// The deployment can't check DNS right now (503).
        case unavailable(String)
        /// The request itself failed (offline, 404, …).
        case failed(String)
    }

    let list: PagedListModel<CustomDomain>
    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void
    private(set) var checks: [Int: Check] = [:]
    private(set) var verifying: Set<Int> = []

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
        self.list = PagedListModel { page in try await client.customDomains(page: page) }
        self.list.onError = onError
    }

    func create(_ input: CustomDomainInput) async throws -> CustomDomain {
        do {
            let created = try await client.createCustomDomain(input)
            list.insert(created)
            return created
        } catch {
            onError(error)
            throw error
        }
    }

    func update(_ original: CustomDomain, to input: CustomDomainInput) async throws -> CustomDomain {
        do {
            let saved = try await client.updateCustomDomain(original, to: input)
            list.replace(saved)
            // A new host is a new question for DNS.
            if saved.host != original.host { checks[saved.id] = nil }
            return saved
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ domain: CustomDomain) async throws {
        do {
            try await client.deleteCustomDomain(id: domain.id)
            list.remove(id: domain.id)
            checks[domain.id] = nil
        } catch {
            onError(error)
            throw error
        }
    }

    /// Runs the DNS check and records what it found. Returns the domain as
    /// the server now has it, when it sent one back.
    @discardableResult
    func verify(_ domain: CustomDomain) async -> CustomDomain? {
        guard !verifying.contains(domain.id) else { return nil }
        verifying.insert(domain.id)
        defer { verifying.remove(domain.id) }
        do {
            let result = try await client.verifyCustomDomain(id: domain.id)
            switch result {
            case .verified(let fresh):
                list.replace(fresh)
                checks[domain.id] = .verified
                return fresh
            case .notVerified(let fresh, let title, let message):
                if let fresh { list.replace(fresh) }
                checks[domain.id] = .pending(title: title, message: message)
                return fresh
            case .unavailable(let message):
                checks[domain.id] = .unavailable(message)
                return nil
            }
        } catch is CancellationError {
            return nil
        } catch {
            onError(error)
            checks[domain.id] = .failed(error.asAPIError.localizedDescription)
            return nil
        }
    }

    func dismissCheck(for id: Int) { checks[id] = nil }

    /// Sample data for previews; skips the first fetch. An empty list shows
    /// the empty state.
    func seed(_ domains: [CustomDomain], checks: [Int: Check] = [:]) {
        for domain in domains.reversed() { list.insert(domain) }
        if domains.isEmpty {
            list.insert(CustomDomain(id: -1, host: ""))
            list.remove(id: -1)
        }
        self.checks = checks
    }
}

/// The registry's `.more` destination: stack-free.
struct DomainsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: DomainsModel
    @State private var isAdding = false
    @State private var pendingDelete: CustomDomain? = nil
    /// A check started from a row, reported in an alert.
    @State private var rowCheck: RowCheck? = nil

    struct RowCheck: Identifiable {
        let domain: CustomDomain
        let check: DomainsModel.Check
        var id: Int { domain.id }
    }

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _model = State(initialValue: DomainsModel(client: client, onError: onError))
    }

    /// For previews.
    init(model: DomainsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ListStateView(
            state: model.list.state,
            empty: .init(
                systemImage: "globe",
                title: String(localized: "No custom domains yet"),
                message: String(localized: "Add one to serve your links from your own branded host."),
                actionTitle: String(localized: "Add Domain"),
                action: { isAdding = true }
            ),
            retry: { [list = model.list] in await list.refresh() }
        ) { domains in
            List {
                ListPageHead(kicker: String(localized: "Organize"),
                             title: String(localized: "Domains"),
                             description: String(localized: "Serve links from your own branded domains."))
                if let error = model.list.refreshError {
                    RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                        .studioClearRow()
                }
                Section {
                    ForEach(Array(domains.enumerated()), id: \.element.id) { index, domain in
                        NavigationLink {
                            DomainDetailView(model: model, domain: domain)
                        } label: {
                            DomainRow(domain: domain, isVerifying: model.verifying.contains(domain.id))
                        }
                        .accessibilityIdentifier("org.domains.row.\(index)")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = domain } label: {
                                ResourceVerb.delete.label
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !domain.isVerified {
                                Button { verify(domain) } label: {
                                    Label("Verify", systemImage: "checkmark.shield")
                                }
                                .tint(Color.studioInfo)
                            }
                        }
                        .contextMenu {
                            if !domain.isVerified {
                                Button { verify(domain) } label: {
                                    Label("Verify Domain", systemImage: "checkmark.shield")
                                }
                            }
                            Button { Pasteboard.copy(domain.address) } label: {
                                Label("Copy Address", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) { pendingDelete = domain } label: {
                                ResourceVerb.delete.label
                            }
                        }
                    }
                    .studioRowBackground()
                    OrganiseLoadMoreRow(list: model.list)
                }
            }
            .studioList()
            .refreshable { [list = model.list] in await list.refresh() }
        }
        .background(Color.studioBg)
        .navigationTitle("Domains")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Domain", systemImage: "plus")
                }
                .accessibilityIdentifier("org.domains.create")
            }
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
        .onChange(of: app.workspaceScope) { _, _ in Task { await model.list.refresh() } }
        .sheet(isPresented: $isAdding) {
            DomainCreateSheet(model: model)
        }
        .alert(
            rowCheck.map { DomainCheckCopy.title(for: $0.check, host: $0.domain.host) } ?? "",
            isPresented: Binding(get: { rowCheck != nil }, set: { if !$0 { rowCheck = nil } }),
            presenting: rowCheck
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { result in
            Text(DomainCheckCopy.message(for: result.check))
        }
        .organiseDeleteFlow(
            $pendingDelete,
            title: String(localized: "Delete this domain?"),
            confirmTitle: { _ in String(localized: "Delete") },
            message: String(localized: "Links served from it stop resolving there. This can’t be undone."),
            delete: { [model] domain in try await model.delete(domain) }
        )
    }

    private func verify(_ domain: CustomDomain) {
        Task {
            await model.verify(domain)
            if let check = model.checks[domain.id] {
                if check == .verified { Haptics.success() }
                rowCheck = RowCheck(domain: domain, check: check)
            }
        }
    }
}

/// Address, then verification, SSL and status pills, then the redirect.
struct DomainRow: View {
    let domain: CustomDomain
    var isVerifying = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            Image(systemName: "globe")
                .foregroundStyle(domain.isVerified ? Color.studioText2 : Color.studioText3)
                .frame(width: StudioSpace.s6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text(verbatim: domain.address)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                let pills = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s1))
                    : AnyLayout(HStackLayout(spacing: StudioSpace.s2))
                pills {
                    if isVerifying {
                        HStack(spacing: StudioSpace.s1) {
                            ProgressView().controlSize(.mini)
                            Text("Verifying…")
                                .studioText(.uiSm)
                                .foregroundStyle(Color.studioText2)
                        }
                    } else {
                        StudioStatusPill(domain.isVerified ? String(localized: "Verified") : String(localized: "Unverified"),
                                         tone: domain.isVerified ? .success : .neutral)
                    }
                    if domain.sslIsEnabled {
                        StudioStatusPill(String(localized: "SSL"), tone: .success)
                    }
                    if !domain.isEnabled {
                        StudioStatusPill(String(localized: "Inactive"), tone: .neutral)
                    }
                }
                Text(domain.redirectTitle)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
    }
}

extension CustomDomain {
    /// The redirect as the web's select names it.
    var redirectTitle: String {
        redirect?.title ?? redirectType
    }
}

extension DomainRedirectType {
    /// The web's `domains.redirect.*` labels.
    var title: String {
        switch self {
        case .permanent: return String(localized: "301 — Permanent redirect")
        case .temporary: return String(localized: "302 — Temporary redirect")
        case .cloak: return String(localized: "Cloak (iframe)")
        case .frame: return String(localized: "Frame")
        }
    }
}

extension DomainKind {
    /// The web's `domains.type.*` labels.
    var title: String {
        switch self {
        case .custom: return String(localized: "Custom domain")
        case .system: return String(localized: "System domain")
        }
    }
}

/// How a verification answer reads, in alerts and banners.
enum DomainCheckCopy {
    static func title(for check: DomainsModel.Check, host: String) -> String {
        switch check {
        case .verified: return String(localized: "Domain verified.")
        case .pending(let title, _): return title
        case .unavailable: return String(localized: "Couldn’t check \(host)")
        case .failed: return String(localized: "Could not verify this domain.")
        }
    }

    static func message(for check: DomainsModel.Check) -> String {
        switch check {
        case .verified:
            return String(localized: "Links on this domain now resolve here.")
        case .pending(_, let message):
            return message ?? String(localized: "DNS changes can take a while to propagate. Verify again later.")
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    static func tone(for check: DomainsModel.Check) -> StudioTone {
        switch check {
        case .verified: return .success
        case .pending: return .warning
        case .unavailable: return .info
        case .failed: return .error
        }
    }
}

#if DEBUG
#Preview("Domains") {
    let model = DomainsModel(client: OrganisePreviewData.client)
    model.seed(OrganisePreviewData.domains)
    return NavigationStack { DomainsView(model: model) }
        .environment(AppModel.preview())
}

#Preview("Domains, empty") {
    let model = DomainsModel(client: OrganisePreviewData.client)
    model.seed([])
    return NavigationStack { DomainsView(model: model) }
        .environment(AppModel.preview())
}
#endif
