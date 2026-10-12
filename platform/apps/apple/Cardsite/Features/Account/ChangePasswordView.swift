import SwiftUI
import StudioKit
import CardsiteKit

/// Current, new and confirm, as on the web. A wrong current password is a
/// 401 that the client sends with `credentialCheck`, so it shows here
/// instead of signing the user out. The session stays valid afterwards.
struct ChangePasswordView: View {
    let model: AccountSettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String? = nil
    @State private var isSaving = false
    @State private var didChange = false

    private var canSubmit: Bool { !current.isEmpty && !new.isEmpty && !confirm.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                if didChange {
                    Section {
                        Label("Password changed successfully", systemImage: "checkmark.circle.fill")
                            .studioText(.ui)
                            .foregroundStyle(Color.studioSuccess)
                        Text("You stay signed in on this device. Other devices keep their sessions until they expire.")
                            .studioText(.uiSm)
                            .studioMuted()
                    }
                } else {
                    Section {
                        SecureField("Current Password", text: $current)
                            .textContentType(.password)
                        SecureField("New Password", text: $new)
                            #if os(iOS) || os(visionOS)
                            .textContentType(.newPassword)
                            #endif
                        SecureField("Confirm New Password", text: $confirm)
                            #if os(iOS) || os(visionOS)
                            .textContentType(.newPassword)
                            #endif
                            .onSubmit { Task { await submit() } }
                    } footer: {
                        VStack(alignment: .leading, spacing: StudioSpace.s2) {
                            Text("Use 8 to 64 characters.")
                            FormErrorText(message: error)
                        }
                    }
                }
            }
            .studioForm()
            .navigationTitle("Change Password")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if didChange {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Change") { Task { await submit() } }
                                .disabled(!canSubmit)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .animation(StudioAnimation.base, value: error)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func submit() async {
        guard canSubmit else { return }
        error = nil
        if let problem = AccountSettingsModel.passwordProblem(new: new, confirm: confirm) {
            error = problem
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.changePassword(current: current, new: new)
            current = ""
            new = ""
            confirm = ""
            didChange = true
            Haptics.success()
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}
