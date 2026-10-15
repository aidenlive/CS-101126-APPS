import SwiftUI
import StudioKit
import CardsiteKit

/*
 GatingSection — what stands between a visitor and the destination:
 password, click limit, expiration URL, sensitive-content warning.

     GatingSection(password: $form.password, hasPassword: detail.settings.hasPassword,
                   clicksLimit: $form.clicksLimitText,
                   expirationURL: $form.settings.expirationURL,
                   sensitiveContent: $form.settings.sensitiveContent,
                   passwordLocked: !options.allowsPasswordProtection,
                   errors: .init(password: errors[.password], …))

 The stored password is a digest, so it is never prefilled (ADR-0083):
 - an empty field means "keep what’s there" (`PasswordChange.keep`);
 - typing sets or replaces it (`.set`);
 - "Remove password protection" is its own switch (`.remove`), shown only
   when one is set.
 With `passwordLocked` (the plan lacks `password_protection`) the field is
 replaced by a plain note; an existing password can still be removed.
 */
struct GatingSection: View {
    struct Errors: Equatable {
        var password: String?
        var clicksLimit: String?
        var expirationURL: String?

        init(password: String? = nil, clicksLimit: String? = nil, expirationURL: String? = nil) {
            self.password = password
            self.clicksLimit = clicksLimit
            self.expirationURL = expirationURL
        }
    }

    @Binding var password: PasswordChange
    let hasPassword: Bool
    @Binding var clicksLimit: String
    @Binding var expirationURL: String
    @Binding var sensitiveContent: Bool
    var passwordLocked: Bool = false
    var errors = Errors()
    var title: String = String(localized: "Gating")

    var body: some View {
        Section {
            passwordRows

            EditorTextField(
                String(localized: "Clicks limit"),
                text: $clicksLimit,
                prompt: String(localized: "No limit"),
                kind: .number,
                help: String(localized: "After this many clicks the address stops resolving."),
                error: errors.clicksLimit
            )

            EditorTextField(
                String(localized: "Expiration URL"),
                text: $expirationURL,
                prompt: "https://example.com/expired",
                kind: .url,
                help: String(localized: "Where visitors go once the limit is reached or the schedule ends."),
                error: errors.expirationURL
            )

            Toggle(isOn: $sensitiveContent) {
                Text("Mark as sensitive content")
            }
            .toggleStyle(.switch)
        } header: {
            EditorSectionHeader(title)
        } footer: {
            Text("Who can open it, and when it stops working.")
        }
        .studioRowBackground()
    }

    @ViewBuilder
    private var passwordRows: some View {
        if passwordLocked {
            LockedFeatureNote(message: String(localized: "Password protection isn’t included in your plan."))
        } else {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text("Password protection")
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                    .accessibilityHidden(true)
                SecureField(String(localized: "Password protection"), text: newPassword,
                            prompt: Text(hasPassword
                                         ? String(localized: "Set — enter a new password to replace it")
                                         : String(localized: "Leave empty to disable")))
                    .labelsHidden()
                    #if os(iOS) || os(visionOS)
                    .textContentType(.newPassword)
                    #endif
                    .studioText(.ui)
                    .disabled(password == .remove)
                EditorFieldFootnote(help: nil, error: errors.password)
            }
            .padding(.vertical, StudioSpace.s1)
        }
        if hasPassword {
            Toggle(isOn: removePassword) {
                Text("Remove password protection")
            }
            .toggleStyle(.switch)
        }
    }

    /// The field's text: only a password being set is ever shown.
    private var newPassword: Binding<String> {
        Binding(
            get: {
                if case .set(let value) = password { return value }
                return ""
            },
            set: { password = $0.isEmpty ? .keep : .set($0) }
        )
    }

    private var removePassword: Binding<Bool> {
        Binding(
            get: { password == .remove },
            set: { password = $0 ? .remove : .keep }
        )
    }
}

#Preview("Gating") {
    @Previewable @State var password = PasswordChange.keep
    @Previewable @State var clicks = "100"
    @Previewable @State var expiration = ""
    @Previewable @State var sensitive = false
    Form {
        GatingSection(password: $password, hasPassword: true, clicksLimit: $clicks,
                      expirationURL: $expiration, sensitiveContent: $sensitive)
        GatingSection(password: $password, hasPassword: false, clicksLimit: $clicks,
                      expirationURL: $expiration, sensitiveContent: $sensitive,
                      passwordLocked: true, title: "Locked")
    }
    .resourceEditorForm()
}
