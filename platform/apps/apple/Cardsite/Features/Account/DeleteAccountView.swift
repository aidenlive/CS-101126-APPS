import SwiftUI
import StudioKit
import CardsiteKit

/// In-app account deletion (App Review 5.1.1(v)).
///
/// The server requires the account password (DELETE /api/v1/account), cancels
/// a paid subscription first, and refuses with 409 `active_subscription` if
/// it cannot (ADR-0175). Accounts created with Google or another provider
/// have no password; they can set one by email from here, then delete.
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var acknowledged = false
    @State private var error: String?
    @State private var isDeleting = false
    @State private var resetState: ResetState = .idle

    enum ResetState: Equatable { case idle, sending, sent, failed(String) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioSpace.s5) {
                    StudioBanner(
                        lead: String(localized: "This is permanent."),
                        message: String(localized: "Your links, QR codes, pages and files are deleted, and their addresses are freed for others. A paid plan is cancelled. Printed QR codes will stop working."),
                        tone: .error
                    )

                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        Text("Password").studioText(.uiSm)
                        SecureField("Your Cardsite password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await delete() } }
                        FormErrorText(message: error)
                    }

                    Toggle("I understand this can't be undone", isOn: $acknowledged)
                        .toggleStyle(.switch)

                    StudioButton(String(localized: "Delete My Account"), systemImage: "trash",
                                 variant: .destructive, isLoading: isDeleting) {
                        Task { await delete() }
                    }
                    .disabled(!acknowledged || password.isEmpty)

                    Divider()

                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        Text("Don't know your password?").studioText(.ui)
                        Text("We'll email you a link to set a new one, then come back here. This also covers accounts first created with Google or another provider on the web.")
                            .studioText(.uiSm).studioMuted()
                        resetControl
                    }
                }
                .padding(StudioSpace.s6)
                .readableWidth(560)
            }
            .background(Color.studioBg)
            .navigationTitle("Delete Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .interactiveDismissDisabled(isDeleting)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var resetControl: some View {
        switch resetState {
        case .idle, .failed:
            StudioButton(String(localized: "Email Me a Password Link"), systemImage: "envelope", variant: .outline) {
                Task { await sendReset() }
            }
            if case .failed(let message) = resetState {
                Text(message).studioText(.uiSm).foregroundStyle(Color.studioError)
            }
        case .sending:
            ProgressView()
        case .sent:
            Label("Sent to \(app.user?.email ?? "your email").", systemImage: "checkmark.circle.fill")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioSuccess)
        }
    }

    private func delete() async {
        guard acknowledged, !password.isEmpty, !isDeleting else { return }
        isDeleting = true
        error = nil
        defer { isDeleting = false }
        do {
            try await app.deleteAccount(password: password)
            // The session has ended; RootView now shows sign-in with a notice.
        } catch {
            app.handle(error)
            self.error = error.asAPIError.localizedDescription
        }
    }

    private func sendReset() async {
        guard let email = app.user?.email, !email.isEmpty else { return }
        resetState = .sending
        do {
            try await app.client.requestPasswordReset(email: email)
            resetState = .sent
        } catch {
            resetState = .failed(error.asAPIError.localizedDescription)
        }
    }
}
