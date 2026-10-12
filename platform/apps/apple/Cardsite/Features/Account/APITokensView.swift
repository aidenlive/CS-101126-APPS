import SwiftUI
import StudioKit
import CardsiteKit

/// Scoped, revocable API tokens (ADR-0002): list, create, revoke.
/// The secret is shown once, right after creation.
struct APITokensView: View {
    let model: AccountSettingsModel

    @State private var isCreating = false
    @State private var pendingRevoke: APIToken? = nil
    @State private var revokeError: String? = nil

    var body: some View {
        ListStateView(
            state: model.tokenListState,
            empty: .init(
                systemImage: "key.horizontal",
                title: String(localized: "No API tokens yet"),
                message: String(localized: "Scoped, revocable credentials for scripts and agents. Each token gets only the scopes you grant."),
                actionTitle: String(localized: "Create Token"),
                action: { isCreating = true }
            ),
            skeleton: .textRows,
            retry: { [model] in await model.loadTokens(force: true) }
        ) { tokens in
            List {
                if let error = model.tokensRefreshError {
                    RefreshErrorBanner(error: error) { model.dismissTokensRefreshError() }
                        .studioClearRow()
                }
                Section {
                    ForEach(tokens) { token in
                        APITokenRow(token: token)
                            .swipeActions(edge: .trailing) {
                                if token.status() == .active {
                                    Button(role: .destructive) { pendingRevoke = token } label: {
                                        Label("Revoke", systemImage: "xmark.circle")
                                    }
                                }
                            }
                            .contextMenu {
                                if token.status() == .active {
                                    Button(role: .destructive) { pendingRevoke = token } label: {
                                        Label("Revoke…", systemImage: "xmark.circle")
                                    }
                                }
                            }
                    }
                } footer: {
                    Text("Scopes are deny-by-default; a write scope implies its read scope. Revoked tokens stay listed as a record.")
                }
                .studioRowBackground()
            }
            .studioList()
            .refreshable { [model] in await model.loadTokens(force: true) }
        }
        .background(Color.studioBg)
        .navigationTitle("API Tokens")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("Create Token", systemImage: "plus")
                }
                .disabled(model.tokens.value == nil)
            }
        }
        .task { [model] in await model.loadTokens() }
        .sheet(isPresented: $isCreating) {
            CreateAPITokenView(model: model)
        }
        .confirmationDialog(
            "Revoke this token?",
            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
            titleVisibility: .visible,
            presenting: pendingRevoke
        ) { token in
            Button("Revoke \(token.name)", role: .destructive) {
                Task { await revoke(token) }
            }
        } message: { _ in
            Text("Requests using this token will be rejected immediately.")
        }
        .alert("Couldn’t revoke", isPresented: Binding(get: { revokeError != nil }, set: { if !$0 { revokeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(revokeError ?? "")
        }
    }

    private func revoke(_ token: APIToken) async {
        do {
            try await model.revokeToken(token)
            Haptics.success()
        } catch {
            revokeError = error.asAPIError.localizedDescription
        }
        pendingRevoke = nil
    }
}

struct APITokenRow: View {
    let token: APIToken

    private var status: (String, StudioTone) {
        switch token.status() {
        case .active: return (String(localized: "Active"), .success)
        case .expired: return (String(localized: "Expired"), .warning)
        case .revoked: return (String(localized: "Revoked"), .neutral)
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let created = token.createdAt {
            parts.append(String(localized: "Created \(created.formatted(date: .abbreviated, time: .omitted))"))
        }
        if let used = token.lastUsedAt {
            parts.append(String(localized: "last used \(used.formatted(.relative(presentation: .named)))"))
        } else {
            parts.append(String(localized: "never used"))
        }
        if let expires = token.expiresAt, token.status() == .active {
            parts.append(String(localized: "expires \(expires.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            HStack(spacing: StudioSpace.s2) {
                Text(verbatim: token.name)
                    .studioText(.ui)
                    .foregroundStyle(token.status() == .active ? Color.studioText : Color.studioText3)
                    .lineLimit(1)
                StudioStatusPill(status.0, tone: status.1)
            }
            Text(verbatim: token.scopes.joined(separator: ", "))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.studioText2)
                .lineLimit(2)
            Text(meta)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
        .padding(.vertical, StudioSpace.s1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Create

/// Name, scopes and an optional expiry. Scopes are offered per resource as
/// None / Read / Read & Write, from the list the server sends.
struct CreateAPITokenView: View {
    let model: AccountSettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var access: [String: ScopeAccess] = [:]
    @State private var expires = false
    @State private var expiry = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var error: String? = nil
    @State private var isSaving = false
    @State private var created: CreatedAPIToken? = nil

    enum ScopeAccess: Hashable { case off, read, write }

    struct ScopeResource: Identifiable {
        let id: String
        let hasRead: Bool
        let hasWrite: Bool
        var title: String { id.replacingOccurrences(of: "-", with: " ").capitalized }
    }

    private var resources: [ScopeResource] {
        let grouped = Dictionary(grouping: model.availableScopes) { scope in
            String(scope.split(separator: ":").first ?? Substring(scope))
        }
        return grouped.keys.sorted().map { key in
            let scopes = grouped[key] ?? []
            return ScopeResource(id: key, hasRead: scopes.contains("\(key):read"), hasWrite: scopes.contains("\(key):write"))
        }
    }

    private var selectedScopes: [String] {
        resources.flatMap { resource -> [String] in
            switch access[resource.id] ?? .off {
            case .off: return []
            case .read: return resource.hasRead ? ["\(resource.id):read"] : []
            case .write:
                var scopes: [String] = []
                if resource.hasRead { scopes.append("\(resource.id):read") }
                if resource.hasWrite { scopes.append("\(resource.id):write") }
                return scopes
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedScopes.isEmpty && !isSaving
    }

    private var earliestExpiry: Date { Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    ScrollView {
                        CreatedTokenPanel(created: created)
                            .padding(StudioSpace.s6)
                            .readableWidth(.sheet)
                    }
                    .background(Color.studioBg)
                } else {
                    form
                }
            }
            .navigationTitle("Create API Token")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if created != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Create") { Task { await create() } }
                                .disabled(!canCreate)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(created != nil || isSaving)
        }
        .cardsiteSheet(.form)
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("deploy script, links agent…"))
                    .plainEntry()
            } footer: {
                Text("A scoped credential for programmatic access. The secret is shown once, right after creation.")
            }
            .studioRowBackground()

            Section {
                ForEach(resources) { resource in
                    Picker(resource.title, selection: binding(for: resource)) {
                        Text("None").tag(ScopeAccess.off)
                        if resource.hasRead { Text("Read").tag(ScopeAccess.read) }
                        if resource.hasWrite { Text("Read & Write").tag(ScopeAccess.write) }
                    }
                }
            } header: {
                Text("Scopes")
            } footer: {
                Text("Scopes are deny-by-default; a write scope implies its read scope.")
            }
            .studioRowBackground()

            Section {
                Toggle("Expires", isOn: $expires.animation(StudioAnimation.base))
                if expires {
                    DatePicker("Expires on", selection: $expiry, in: earliestExpiry..., displayedComponents: .date)
                }
            } footer: {
                FormErrorText(message: error)
            }
            .studioRowBackground()
        }
        .studioForm()
    }

    private func binding(for resource: ScopeResource) -> Binding<ScopeAccess> {
        Binding(get: { access[resource.id] ?? .off }, set: { access[resource.id] = $0 })
    }

    private func create() async {
        guard canCreate else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            created = try await model.createToken(
                name: name.trimmingCharacters(in: .whitespaces),
                scopes: selectedScopes,
                expiresAt: expires ? Calendar.current.startOfDay(for: expiry).addingTimeInterval(86_399) : nil
            )
            Haptics.success()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

/// The new token's secret, shown this once.
struct CreatedTokenPanel: View {
    let created: CreatedAPIToken

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            StudioBanner(
                lead: String(localized: "Token created."),
                message: String(localized: "Copy this secret now — it is shown only this once. Only a hash is stored on the server."),
                tone: .success
            )
            StudioCard {
                VStack(alignment: .leading, spacing: StudioSpace.s3) {
                    Text(verbatim: created.token.name)
                        .studioText(.ui)
                    HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                        Text(verbatim: created.secret)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("Secret"))
                        Spacer(minLength: StudioSpace.s2)
                        SecretCopyButton(value: created.secret, label: String(localized: "Copy secret"))
                    }
                    Text(verbatim: created.token.scopes.joined(separator: ", "))
                        .studioText(.uiSm)
                        .studioMuted()
                }
            }
        }
    }
}

#if DEBUG
#Preview("API tokens") {
    let model = AccountSettingsModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed(
        twoFactor: TwoFactorStatus(isEnabled: true, remainingRecoveryCodes: 9),
        tokens: APITokenList(
            scopes: ["account:read", "links:read", "links:write", "qr:read", "qr:write", "uploads:read", "uploads:write"],
            tokens: [
                APIToken(id: 3, name: "Shortcuts", scopes: ["links:read", "links:write"],
                         lastUsedAt: .now.addingTimeInterval(-7_200), createdAt: .now.addingTimeInterval(-864_000)),
                APIToken(id: 2, name: "Old deploy script", scopes: ["qr:read"],
                         revokedAt: .now.addingTimeInterval(-86_400), createdAt: .now.addingTimeInterval(-2_592_000)),
            ]
        )
    )
    return NavigationStack { APITokensView(model: model) }
        .environment(AppModel.preview())
}

#Preview("Create token") {
    let model = AccountSettingsModel(client: APIClient(baseURL: AppConfiguration.preview.apiBaseURL))
    model.seed(
        twoFactor: TwoFactorStatus(isEnabled: false, remainingRecoveryCodes: 0),
        tokens: APITokenList(scopes: ["account:read", "links:read", "links:write", "qr:read", "qr:write"], tokens: [])
    )
    return CreateAPITokenView(model: model)
}
#endif
