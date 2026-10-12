import SwiftUI
import StudioKit
import CardsiteKit

/// The Mac `Settings` scene (⌘,): General, Security and Preferences.
///
/// Wire it in `CardsiteApp` inside `#if os(macOS)`:
///
///     Settings { CardsiteSettingsView().environment(model) }
struct CardsiteSettingsView: View {
    @Environment(AppModel.self) private var app

    enum Pane: String, Hashable {
        case general, security, preferences
    }

    @AppStorage("settings.pane") private var pane: Pane = .general

    var body: some View {
        Group {
            if app.user != nil {
                SignedInSettings(client: app.client, onError: { [app] in app.handle($0) }, pane: $pane)
            } else {
                ContentUnavailableView(
                    "Not signed in",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Sign in to Cardsite to change your settings.")
                )
                .padding(StudioSpace.s8)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440)
        #endif
    }
}

private struct SignedInSettings: View {
    @State private var settings: AccountSettingsModel
    @Binding var pane: CardsiteSettingsView.Pane
    private let client: APIClient
    private let onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void, pane: Binding<CardsiteSettingsView.Pane>) {
        _settings = State(initialValue: AccountSettingsModel(client: client, onError: onError))
        _pane = pane
        self.client = client
        self.onError = onError
    }

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "person.crop.circle", value: CardsiteSettingsView.Pane.general) {
                GeneralSettingsPane(settings: settings)
            }
            Tab("Security", systemImage: "lock.shield", value: CardsiteSettingsView.Pane.security) {
                SecuritySettingsPane(settings: settings)
            }
            Tab("Preferences", systemImage: "slider.horizontal.3", value: CardsiteSettingsView.Pane.preferences) {
                PreferencesView(client: client, onError: onError, inlineSave: true)
            }
        }
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var app
    let settings: AccountSettingsModel
    @State private var isEditingName = false
    @State private var isPickingTimezone = false

    private var timezone: String {
        settings.savedTimezone ?? app.user?.timezone ?? TimeZone.current.identifier
    }

    var body: some View {
        Form {
            if let user = app.user {
                Section("Profile") {
                    LabeledContent("Name") {
                        HStack(spacing: StudioSpace.s2) {
                            Text(user.name.isEmpty ? String(localized: "Not set") : user.name)
                            Button("Edit…") { isEditingName = true }
                        }
                    }
                    LabeledContent("Email") {
                        Text(verbatim: user.email).textSelection(.enabled)
                    }
                    LabeledContent("Timezone") {
                        HStack(spacing: StudioSpace.s2) {
                            Text(verbatim: timezone.replacingOccurrences(of: "_", with: " "))
                            Button("Change…") { isPickingTimezone = true }
                                .disabled(app.needsProfile)
                        }
                    }
                }
            }
            Section("About") {
                Link("Privacy Policy", destination: app.configuration.privacyURL)
                Link("Terms of Service", destination: app.configuration.termsURL)
                Link("Contact Support", destination: app.configuration.supportURL)
                LabeledContent("Version", value: Bundle.main.versionDescription)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isEditingName) { AccountNameEditor() }
        .sheet(isPresented: $isPickingTimezone) {
            TimezonePickerView(model: settings, current: timezone)
        }
    }
}

// MARK: - Security

private struct SecuritySettingsPane: View {
    let settings: AccountSettingsModel

    enum Sheet: String, Identifiable {
        case password, enable, disable, regenerate, createToken
        var id: String { rawValue }
    }

    @State private var sheet: Sheet? = nil
    @State private var pendingRevoke: APIToken? = nil
    @State private var revokeError: String? = nil

    var body: some View {
        Form {
            Section("Password") {
                Button("Change Password…") { sheet = .password }
            }

            Section {
                twoFactor
            } header: {
                Text("Two-Factor Authentication")
            } footer: {
                Text("Add an extra layer of security with a time-based one-time password (TOTP) app.")
            }

            Section {
                tokens
            } header: {
                HStack {
                    Text("API Tokens")
                    Spacer()
                    Button {
                        sheet = .createToken
                    } label: {
                        Label("Create Token", systemImage: "plus")
                    }
                    .disabled(settings.tokens.value == nil)
                }
            } footer: {
                Text("Scoped, revocable credentials for scripts and agents. Each token gets only the scopes you grant.")
            }
        }
        .formStyle(.grouped)
        .task { [settings] in await settings.loadTwoFactor() }
        .task { [settings] in await settings.loadTokens() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .password: ChangePasswordView(model: settings)
            case .enable: TwoFactorSetupView(model: settings)
            case .disable: TwoFactorPasswordView(model: settings, purpose: .disable)
            case .regenerate: TwoFactorPasswordView(model: settings, purpose: .regenerate)
            case .createToken: CreateAPITokenView(model: settings)
            }
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

    @ViewBuilder
    private var twoFactor: some View {
        switch settings.twoFactor {
        case .idle, .loading:
            HStack { Text("Status"); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let error):
            LabeledContent("Status") {
                Button("Try Again") { Task { await settings.loadTwoFactor(force: true) } }
            }
            Text(error.localizedDescription)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioError)
        case .loaded(let status):
            LabeledContent("Status") {
                StudioStatusPill(status.isEnabled ? String(localized: "On") : String(localized: "Off"),
                                 tone: status.isEnabled ? .success : .neutral)
            }
            if status.isEnabled {
                LabeledContent("Recovery codes left") {
                    Text(status.remainingRecoveryCodes.grouped).monospacedDigit()
                }
                HStack {
                    Button("Generate New Recovery Codes…") { sheet = .regenerate }
                    Spacer()
                    Button("Disable 2FA…", role: .destructive) { sheet = .disable }
                }
            } else {
                Button("Enable 2FA…") { sheet = .enable }
            }
        }
    }

    @ViewBuilder
    private var tokens: some View {
        switch settings.tokenListState {
        case .idle, .loading:
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
        case .failed(let error):
            HStack {
                Text(error.localizedDescription)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioError)
                Spacer()
                Button("Try Again") { Task { await settings.loadTokens(force: true) } }
            }
        case .loaded(let list) where list.isEmpty:
            Text("No API tokens yet.")
                .studioText(.uiSm)
                .studioMuted()
        case .loaded(let list):
            if let error = settings.tokensRefreshError {
                RefreshErrorBanner(error: error) { settings.dismissTokensRefreshError() }
            }
            ForEach(list) { token in
                HStack(alignment: .top) {
                    APITokenRow(token: token)
                    Spacer()
                    if token.status() == .active {
                        Button("Revoke…", role: .destructive) { pendingRevoke = token }
                            .accessibilityLabel(Text("Revoke \(token.name)"))
                    }
                }
            }
        }
    }

    private func revoke(_ token: APIToken) async {
        do {
            try await settings.revokeToken(token)
        } catch {
            revokeError = error.asAPIError.localizedDescription
        }
        pendingRevoke = nil
    }
}

#if DEBUG
#Preview("Settings") {
    CardsiteSettingsView()
        .environment(AppModel.preview())
}
#endif
