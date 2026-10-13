import SwiftUI
import StudioKit
import CardsiteKit

/// Sign in, create an account, two-factor step and password reset.
///
/// Email and password only. The API's OAuth providers redirect to the web
/// app and offer no native exchange, and adding any third-party sign-in here
/// would also require Sign in with Apple (App Review 4.8), which the API does
/// not support yet. See docs/launch/native-apple.md.
struct AuthFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var mode: Mode = .signIn

    enum Mode: Equatable { case signIn, register, twoFactor(email: String, password: String), forgotPassword }

    var body: some View {
        ScrollView {
            VStack(spacing: StudioSpace.s8) {
                VStack(spacing: StudioSpace.s4) {
                    BrandMark(size: 56)
                    StudioTwoToneTitle(String(localized: "Every resource is a "), accent: String(localized: "link."), style: .display)
                        .multilineTextAlignment(.center)
                    Text("Create, host, and share pages, links, QR codes, sites, files, and more in seconds.")
                        .studioText(.lead)
                        .studioMuted()
                        .multilineTextAlignment(.center)
                }

                if let notice = app.signOutNotice {
                    StudioBanner(lead: String(localized: "Signed out."), message: notice, tone: .info)
                }

                StudioCard {
                    Group {
                        switch mode {
                        case .signIn:
                            SignInForm(mode: $mode)
                        case .register:
                            RegisterForm(mode: $mode)
                        case .twoFactor(let email, let password):
                            TwoFactorForm(email: email, password: password, mode: $mode)
                        case .forgotPassword:
                            ForgotPasswordForm(mode: $mode)
                        }
                    }
                }
            }
            .padding(.horizontal, StudioSpace.s5)
            .padding(.vertical, StudioSpace.s10)
            .readableWidth(.narrow)
        }
        .dismissesKeyboardOnScroll()
        .background(Color.studioBg.ignoresSafeArea())
        // A short ease (a cross-fade in effect) as the forms swap, so the
        // card's height change never springs, with or without Reduce Motion.
        .animation(StudioAnimation.base, value: mode)
    }
}

// MARK: - Sign in

private struct SignInForm: View {
    @Environment(AppModel.self) private var app
    @Binding var mode: AuthFlowView.Mode
    @State private var email = ""
    @State private var password = ""
    @State private var error: String? = nil
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            Text("Sign in").studioText(.title)
            StudioTextField(String(localized: "Email"), text: $email, placeholder: "you@example.com")
                .plainEntry()
                #if os(iOS) || os(visionOS)
                .keyboardType(.emailAddress)
                #endif
                .textContentType(.username)
            PasswordField(title: String(localized: "Password"), text: $password, isNew: false)
                .onSubmit { Task { await submit() } }
            FormErrorText(message: error)
            StudioButton(String(localized: "Sign In"), variant: .primary, isLoading: isWorking) {
                Task { await submit() }
            }
            .disabled(email.isEmpty || password.isEmpty)
            .accessibilityIdentifier("auth.signIn")
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Forgot Password?") { mode = .forgotPassword }
                Spacer()
                Button("Create an Account") { mode = .register }
                    .accessibilityIdentifier("auth.toSignUp")
            }
            .buttonStyle(.borderless)
            .studioText(.uiSm)
        }
    }

    private func submit() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let outcome = try await app.signIn(email: email, password: password)
            if outcome == .twoFactorRequired {
                mode = .twoFactor(email: email, password: password)
            }
        } catch {
            self.error = AuthErrorText.describe(error)
        }
    }
}

// MARK: - Two-factor

private struct TwoFactorForm: View {
    @Environment(AppModel.self) private var app
    let email: String
    let password: String
    @Binding var mode: AuthFlowView.Mode
    @State private var code = ""
    @State private var useRecoveryCode = false
    @State private var error: String? = nil
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            Text("Two-factor authentication").studioText(.title)
            Text(useRecoveryCode
                 ? String(localized: "Enter one of the recovery codes you saved when you turned on two-factor authentication.")
                 : String(localized: "Enter the 6-digit code from your authenticator app."))
                .studioText(.uiSm)
                .studioMuted()
            StudioTextField(useRecoveryCode ? String(localized: "Recovery code") : String(localized: "Code"),
                            text: $code, placeholder: useRecoveryCode ? "xxxx-xxxx" : "123456")
                .plainEntry()
                #if os(iOS) || os(visionOS)
                .keyboardType(useRecoveryCode ? .asciiCapable : .numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .onSubmit { Task { await submit() } }
            FormErrorText(message: error)
            StudioButton(String(localized: "Verify"), variant: .primary, isLoading: isWorking) {
                Task { await submit() }
            }
            .disabled(code.isEmpty)
            HStack {
                Button(useRecoveryCode ? "Use authenticator code" : "Use a recovery code") {
                    useRecoveryCode.toggle()
                    code = ""
                    error = nil
                }
                Spacer()
                Button("Back") { mode = .signIn }
            }
            .buttonStyle(.borderless)
            .studioText(.uiSm)
        }
    }

    private func submit() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let outcome = try await app.signIn(
                email: email, password: password,
                twoFactorCode: useRecoveryCode ? nil : trimmed,
                recoveryCode: useRecoveryCode ? trimmed : nil
            )
            if outcome == .twoFactorRequired {
                error = String(localized: "That code didn’t work. Check it and try again.")
            }
        } catch {
            self.error = AuthErrorText.describe(error)
        }
    }
}

// MARK: - Register

private struct RegisterForm: View {
    @Environment(AppModel.self) private var app
    @Binding var mode: AuthFlowView.Mode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String? = nil
    @State private var isWorking = false

    private var passwordProblem: String? {
        if password.isEmpty { return nil }
        if password.count < 8 { return String(localized: "Use at least 8 characters.") }
        if password.count > 64 { return String(localized: "Use 64 characters or fewer.") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            Text("Create your account").studioText(.title)
            StudioTextField(String(localized: "Name"), text: $name, placeholder: String(localized: "Alex Morgan"))
                #if os(iOS) || os(visionOS)
                .textContentType(.name)
                #endif
            StudioTextField(String(localized: "Email"), text: $email, placeholder: "you@example.com")
                .plainEntry()
                #if os(iOS) || os(visionOS)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                #endif
            PasswordField(title: String(localized: "Password"), text: $password, isNew: true,
                          help: String(localized: "8 to 64 characters."), errorMessage: passwordProblem)
                .onSubmit { Task { await submit() } }
            FormErrorText(message: error)
            StudioButton(String(localized: "Create Account"), variant: .primary, isLoading: isWorking) {
                Task { await submit() }
            }
            .disabled(name.isEmpty || email.isEmpty || password.isEmpty || passwordProblem != nil)
            .accessibilityIdentifier("auth.signUp")

            Text(consent)
                .studioText(.uiSm)
                .studioMuted()

            Button("I already have an account") { mode = .signIn }
                .buttonStyle(.borderless)
                .studioText(.uiSm)
        }
    }

    /// Markdown built at runtime so the URLs come from configuration.
    private var consent: AttributedString {
        let terms = app.configuration.termsURL.absoluteString
        let privacy = app.configuration.privacyURL.absoluteString
        let format = String(localized: "By creating an account you agree to the [Terms of Service](\(terms)) and [Privacy Policy](\(privacy)).")
        return (try? AttributedString(markdown: format)) ?? AttributedString(format)
    }

    private func submit() async {
        guard !isWorking, passwordProblem == nil else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await app.register(name: name, email: email, password: password)
        } catch let apiError as APIError {
            if case .conflict = apiError {
                error = String(localized: "An account with this email already exists. Sign in instead.")
            } else {
                error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Forgot password

private struct ForgotPasswordForm: View {
    @Environment(AppModel.self) private var app
    @Binding var mode: AuthFlowView.Mode
    @State private var email = ""
    @State private var sent = false
    @State private var error: String? = nil
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            Text("Reset your password").studioText(.title)
            if sent {
                StudioBanner(lead: String(localized: "Check your email."),
                             message: String(localized: "If an account exists for \(email), a reset link is on its way. Open it on any device, then sign in here."),
                             tone: .success)
            } else {
                Text("We’ll email you a link to choose a new password.")
                    .studioText(.uiSm).studioMuted()
                StudioTextField(String(localized: "Email"), text: $email, placeholder: "you@example.com")
                    .plainEntry()
                    #if os(iOS) || os(visionOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    #endif
                    .onSubmit { Task { await submit() } }
                FormErrorText(message: error)
                StudioButton(String(localized: "Send Reset Link"), variant: .primary, isLoading: isWorking) {
                    Task { await submit() }
                }
                .disabled(email.isEmpty)
            }
            Button("Back to Sign In") { mode = .signIn }
                .buttonStyle(.borderless)
                .studioText(.uiSm)
        }
    }

    private func submit() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await app.client.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            sent = true
        } catch {
            self.error = AuthErrorText.describe(error)
        }
    }
}

// MARK: - Password field

/// Secure entry with a show/hide control, styled to sit with StudioTextField.
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var isNew: Bool
    var help: String?
    var errorMessage: String?
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    // Mirrors StudioTextField (label, fill, hairline, focus ring) so the
    // email and password fields read as one set.
    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Text(title)
                .studioText(.uiSm)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioText)
            HStack(spacing: StudioSpace.s2) {
                Group {
                    if isRevealed {
                        TextField(title, text: $text)
                    } else {
                        SecureField(title, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .studioText(.ui)
                .focused($isFocused)
                .plainEntry()
                #if os(iOS) || os(visionOS)
                .textContentType(isNew ? .newPassword : .password)
                #else
                // AppKit's NSTextContentType has no new-password type.
                .textContentType(.password)
                #endif
                .labelsHidden()
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(Color.studioText3)
                        .frame(minWidth: StudioLayout.tapTarget, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? Text("Hide Password") : Text("Show Password"))
            }
            .padding(.leading, StudioSpace.s3)
            // StudioTextField's 42 pt field height (control height + 6).
            .frame(minHeight: StudioLayout.controlHeight + StudioSpace.s1 + StudioSpace.s1 / 2)
            .background(
                RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                    .fill(isFocused ? Color.studioSurface : Color.studioSurface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                    .strokeBorder(errorMessage == nil ? (isFocused ? Color.studioBorderStrong : Color.studioBorder) : Color.studioError,
                                  lineWidth: isFocused || errorMessage != nil ? 1 : 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                    .strokeBorder(Color.studioAccentGlow, lineWidth: isFocused && errorMessage == nil ? 3 : 0)
                    .padding(-StudioSpace.s1 / 2)
            )
            .animation(StudioAnimation.base, value: isFocused)
            if let errorMessage {
                Text(errorMessage).studioText(.uiSm).foregroundStyle(Color.studioError)
            } else if let help {
                Text(help).studioText(.uiSm).studioMuted()
            }
        }
    }
}

/// The sign-in error line. Debug builds add where the app was trying to
/// connect, because "Can't reach Cardsite" during development almost always
/// means the local API isn't running.
enum AuthErrorText {
    static func describe(_ error: Error) -> String {
        let apiError = error.asAPIError
        var text = apiError.localizedDescription
        #if DEBUG
        if case .transport = apiError, !FixtureMode.isEnabled {
            text += " " + String(localized: "(Debug: no API at \(AppConfiguration.current.apiBaseURL.absoluteString). Start it, set Config/Local.xcconfig, or run the Cardsite Demo scheme.)")
        }
        #endif
        return text
    }
}
