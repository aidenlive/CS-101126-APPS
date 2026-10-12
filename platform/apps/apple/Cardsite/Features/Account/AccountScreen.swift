import SwiftUI
import StudioKit
import CardsiteKit

/// Profile, plan (read-only), legal, sign out and account deletion.
///
/// The plan is shown but not sold or linked to: App Review 3.1.1 forbids
/// steering to outside purchases in most storefronts, and the app has no
/// in-app purchase (docs/launch/native-apple.md → Purchasing).
struct AccountScreen: View {
    @Environment(AppModel.self) private var app
    @State private var plan: Loadable<(AccountPlan, Plan?)> = .idle
    @State private var isEditingName = false
    @State private var isDeleting = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = app.user {
                    Section {
                        HStack(spacing: StudioSpace.s3) {
                            Text(user.initial)
                                .studioText(.titleSm)
                                .foregroundStyle(Color.studioAccentInk)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Color.studioAccent))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name.isEmpty ? String(localized: "Your account") : user.name)
                                    .studioText(.ui)
                                Text(verbatim: user.email)
                                    .studioText(.uiSm)
                                    .studioMuted()
                            }
                        }
                        .accessibilityElement(children: .combine)
                        Button("Edit Name") { isEditingName = true }
                    }

                    Section("Plan") {
                        planRow
                    }

                    Section("Security") {
                        LabeledContent("Two-factor authentication",
                                       value: user.twoFactorEnabled == true ? String(localized: "On") : String(localized: "Off"))
                        Text("Manage passwords and two-factor authentication on cardsite.com.")
                            .studioText(.uiSm)
                            .studioMuted()
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
                    Button("Delete Account…", role: .destructive) { isDeleting = true }
                } footer: {
                    Text("Deleting your account removes your links, QR codes, pages and files, and frees their addresses. It can't be undone.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Account")
            .task {
                if app.needsProfile { await app.refreshUser() }
                await loadPlan()
            }
            .refreshable {
                // Not refreshUser(): the server caches GET /user for ~10 min
                // and would bring back a name the user just changed.
                if app.needsProfile { await app.refreshUser() }
                await loadPlan(force: true)
            }
            .sheet(isPresented: $isEditingName) { NameEditor() }
            .sheet(isPresented: $isDeleting) { DeleteAccountView() }
            .confirmationDialog("Sign out of Cardsite?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
            }
        }
    }

    @ViewBuilder
    private var planRow: some View {
        switch plan {
        case .idle, .loading:
            HStack { Text("Current plan"); Spacer(); ProgressView() }
        case .failed:
            Button("Couldn't load your plan. Try again.") { Task { await loadPlan(force: true) } }
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

    private func loadPlan(force: Bool = false) async {
        if !force, plan.value != nil { return }
        if plan.value == nil { plan = .loading }
        let client = app.client
        do {
            async let account = client.accountPlan()
            async let plans = client.plans()
            let (a, all) = try await (account, plans)
            plan = .loaded((a, all.first { $0.id == a.planID }))
        } catch {
            app.handle(error)
            if plan.value == nil { plan = .failed(error.asAPIError) }
        }
    }
}

private struct NameEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                StudioTextField(String(localized: "Name"), text: $name, errorMessage: error)
                    #if os(iOS)
                    .textContentType(.name)
                    #endif
                    .onSubmit { Task { await save() } }
                Spacer()
            }
            .padding(StudioSpace.s6)
            .background(Color.studioBg)
            .navigationTitle("Edit Name")
            #if os(iOS)
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
