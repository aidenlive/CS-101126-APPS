import SwiftUI
import StudioKit
import CardsiteKit

/// Profile, plan (read-only), security, preferences, legal, sign out and
/// account deletion.
///
/// The plan is shown but not sold or linked to: App Review 3.1.1 forbids
/// steering to outside purchases in most storefronts, and the app has no
/// in-app purchase (docs/launch/native-apple.md → Purchasing).
struct AccountScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            AccountView(client: app.client, onError: { [app] in app.handle($0) })
        }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var app
    @State private var settings: AccountSettingsModel
    @State private var sheet: Sheet? = nil
    @State private var confirmSignOut = false

    enum Sheet: String, Identifiable {
        case editName, timezone, password, enableTwoFactor, disableTwoFactor, recoveryCodes, deleteAccount
        var id: String { rawValue }
    }

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void) {
        _settings = State(initialValue: AccountSettingsModel(client: client, onError: onError))
    }

    var body: some View {
        Form {
            if let user = app.user {
                profileSection(user)

                Section("Plan") {
                    planRow
                }

                securitySection

                Section {
                    NavigationLink {
                        PreferencesView(client: app.client, onError: { [app] in app.handle($0) })
                    } label: {
                        Label("Preferences", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        ActivityLogsView(client: app.client, onError: { [app] in app.handle($0) })
                    } label: {
                        Label("Activity Logs", systemImage: "list.bullet.rectangle")
                    }
                }
            }

            Section("About") {
                Link("Privacy Policy", destination: app.configuration.privacyURL)
                Link("Terms of Service", destination: app.configuration.termsURL)
                Link("Contact Support", destination: app.configuration.supportURL)
                LabeledContent("Version", value: Bundle.main.versionDescription)
            }

            Section {
                Button("Sign Out") { confirmSignOut = true }
                Button("Delete Account…", role: .destructive) { sheet = .deleteAccount }
                    .accessibilityIdentifier("account.delete")
            } footer: {
                Text("Deleting your account removes your links, QR codes, pages and files, and frees their addresses. It can't be undone.")
            }
        }
        .studioForm()
        .navigationTitle("Account")
        .task { [app, settings] in
            if app.needsProfile { await app.refreshUser() }
            await settings.loadPlan()
        }
        .task { [settings] in await settings.loadTwoFactor() }
        // Captures the models, not the view: the closure is `@Sendable`.
        // Not an unconditional `refreshUser()`: the server caches GET /user
        // for ~10 min and would bring back a name the user just changed.
        .refreshable { [app, settings] in
            if app.needsProfile { await app.refreshUser() }
            await settings.loadPlan(force: true)
            await settings.loadTwoFactor(force: true)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .editName: AccountNameEditor()
            case .timezone: TimezonePickerView(model: settings, current: currentTimezone)
            case .password: ChangePasswordView(model: settings)
            case .enableTwoFactor: TwoFactorSetupView(model: settings)
            case .disableTwoFactor: TwoFactorPasswordView(model: settings, purpose: .disable)
            case .recoveryCodes: TwoFactorPasswordView(model: settings, purpose: .regenerate)
            case .deleteAccount: DeleteAccountView()
            }
        }
        .confirmationDialog("Sign out of Cardsite?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
        }
    }

    private var currentTimezone: String {
        settings.savedTimezone ?? app.user?.timezone ?? TimeZone.current.identifier
    }

    // MARK: Profile

    private func profileSection(_ user: User) -> some View {
        Section {
            HStack(spacing: StudioSpace.s3) {
                Text(user.initial)
                    .studioText(.titleSm)
                    .foregroundStyle(Color.studioAccentInk)
                    .frame(width: StudioSpace.s12, height: StudioSpace.s12)
                    .background(Circle().fill(Color.studioAccent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(user.name.isEmpty ? String(localized: "Your account") : user.name)
                        .studioText(.ui)
                    Text(verbatim: user.email)
                        .studioText(.uiSm)
                        .studioMuted()
                }
            }
            .accessibilityElement(children: .combine)
            Button("Edit Name") { sheet = .editName }
            Button {
                sheet = .timezone
            } label: {
                LabeledContent("Timezone") {
                    Text(verbatim: currentTimezone.replacingOccurrences(of: "_", with: " "))
                }
            }
            .disabled(app.needsProfile)
        }
    }

    // MARK: Security

    @ViewBuilder
    private var securitySection: some View {
        Section {
            Button("Change Password…") { sheet = .password }
            twoFactorRows
            NavigationLink {
                APITokensView(model: settings)
            } label: {
                Text("API Tokens")
            }
        } header: {
            Text("Security")
        } footer: {
            Text("Two-factor authentication adds a time-based one-time password (TOTP) from an authenticator app to every sign-in.")
        }
    }

    @ViewBuilder
    private var twoFactorRows: some View {
        switch settings.twoFactor {
        case .idle, .loading:
            HStack {
                Text("Two-factor authentication")
                Spacer()
                ProgressView()
            }
        case .failed(let error):
            Button {
                Task { await settings.loadTwoFactor(force: true) }
            } label: {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Two-factor authentication")
                    Text(error == .offline
                         ? String(localized: "You're offline. Tap to try again.")
                         : String(localized: "Couldn't load its status. Tap to try again."))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioError)
                }
            }
        case .loaded(let status):
            LabeledContent("Two-factor authentication") {
                StudioStatusPill(status.isEnabled ? String(localized: "On") : String(localized: "Off"),
                                 tone: status.isEnabled ? .success : .neutral)
            }
            if status.isEnabled {
                LabeledContent("Recovery codes left") {
                    Text(status.remainingRecoveryCodes.grouped)
                        .monospacedDigit()
                        .foregroundStyle(status.remainingRecoveryCodes <= 2 ? Color.studioWarning : Color.studioText2)
                }
                Button("Generate New Recovery Codes…") { sheet = .recoveryCodes }
                Button("Disable 2FA…", role: .destructive) { sheet = .disableTwoFactor }
            } else {
                Button("Enable 2FA…") { sheet = .enableTwoFactor }
            }
        }
    }

    // MARK: Plan

    @ViewBuilder
    private var planRow: some View {
        switch settings.plan {
        case .idle, .loading:
            HStack { Text("Current plan"); Spacer(); ProgressView() }
        case .failed:
            Button("Couldn't load your plan. Try again.") { Task { await settings.loadPlan(force: true) } }
        case .loaded(let (account, details)):
            LabeledContent("Current plan", value: details?.name ?? String(localized: "Unknown"))
            if let limit = details?.settings?.customSlugsLimit {
                LabeledContent("Custom addresses", value: limit < 0 ? String(localized: "Unlimited") : limit.grouped)
            }
            if let expiry = account.planExpirationDate {
                LabeledContent("Renews or ends", value: expiry.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }
}

struct AccountNameEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String? = nil
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                StudioTextField(String(localized: "Name"), text: $name, errorMessage: error)
                    #if os(iOS) || os(visionOS)
                    .textContentType(.name)
                    #endif
                    .onSubmit { Task { await save() } }
                Spacer()
            }
            .padding(StudioSpace.s6)
            .background(Color.studioBg)
            .navigationTitle("Edit Name")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { name = app.user?.name ?? "" }
        }
        .presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 200)
        #endif
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.updateName(name)
            dismiss()
        } catch {
            app.handle(error)
            self.error = error.asAPIError.localizedDescription
        }
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#if DEBUG
#Preview("Account") {
    AccountScreen()
        .environment(AppModel.preview())
}
#endif
