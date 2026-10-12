import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import UniformTypeIdentifiers
import StudioKit
import CardsiteKit

// MARK: - Enable

/// Turning on two-factor authentication: scan (or type) the secret, confirm
/// with a 6-digit code, then keep the recovery codes, which are shown once.
///
/// The QR code is drawn on the device from `provisioning_url`. The web sends
/// it to a third-party QR service; the secret never leaves the app here.
struct TwoFactorSetupView: View {
    let model: AccountSettingsModel

    @Environment(\.dismiss) private var dismiss
    @State private var setup: Loadable<TwoFactorSetup> = .idle
    @State private var code = ""
    @State private var error: String? = nil
    @State private var isVerifying = false
    @State private var recoveryCodes: [String]? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let recoveryCodes {
                    ScrollView {
                        RecoveryCodesPanel(
                            codes: recoveryCodes,
                            lead: String(localized: "Two-factor authentication is on.")
                        )
                        .padding(StudioSpace.s6)
                        .readableWidth(.sheet)
                    }
                } else {
                    switch setup {
                    case .idle, .loading:
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Loading")
                    case .failed(let error):
                        ErrorStateView(error: error) { await start() }
                    case .loaded(let setup):
                        enrol(setup)
                    }
                }
            }
            .background(Color.studioBg)
            .navigationTitle("Enable 2FA")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if recoveryCodes != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            // The codes exist only in this sheet; a swipe must not lose them.
            .interactiveDismissDisabled(recoveryCodes != nil || isVerifying)
            .task { if case .idle = setup { await start() } }
        }
        .cardsiteSheet(.form)
    }

    private func enrol(_ setup: TwoFactorSetup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpace.s6) {
                Text("Scan the QR code in your authenticator app (Google Authenticator, Authy, etc.), then enter the 6-digit code below.")
                    .studioText(.body)
                    .foregroundStyle(Color.studioText2)
                    .fixedSize(horizontal: false, vertical: true)

                StudioCard {
                    VStack(spacing: StudioSpace.s4) {
                        ProvisioningQRCode(payload: setup.provisioningURL)
                            .frame(maxWidth: .infinity)

                        if let url = URL(string: setup.provisioningURL) {
                            Link(destination: url) {
                                Label("Open in Authenticator", systemImage: "arrow.up.forward.app")
                                    .studioText(.ui)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: StudioSpace.s2) {
                    Text("Or enter this key by hand")
                        .studioText(.uiSm)
                        .fontWeight(.semibold)
                    HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                        Text(verbatim: setup.secret.chunked(by: 4))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("Setup key"))
                            .accessibilityValue(Text(verbatim: setup.secret))
                        Spacer(minLength: StudioSpace.s2)
                        SecretCopyButton(value: setup.secret, label: String(localized: "Copy setup key"))
                    }
                }

                VStack(alignment: .leading, spacing: StudioSpace.s2) {
                    Text("Verification Code")
                        .studioText(.uiSm)
                        .fontWeight(.semibold)
                    HStack(spacing: StudioSpace.s3) {
                        TextField("123456", text: $code)
                            .textContentType(.oneTimeCode)
                            .font(.system(.title3, design: .monospaced))
                            .plainEntry()
                            #if os(iOS) || os(visionOS)
                            .keyboardType(.numberPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: code) { _, value in
                                let digits = String(value.filter(\.isASCIIDigit).prefix(6))
                                if digits != value { code = digits }
                            }
                            .onSubmit { Task { await verify() } }
                        StudioButton(String(localized: "Verify"), systemImage: "checkmark.shield",
                                     variant: .primary, isLoading: isVerifying) {
                            Task { await verify() }
                        }
                        .disabled(code.count != 6)
                    }
                    FormErrorText(message: error)
                }
            }
            .padding(StudioSpace.s6)
            .readableWidth(.sheet)
            .animation(StudioAnimation.base, value: error)
        }
    }

    private func start() async {
        setup = .loading
        do {
            setup = .loaded(try await model.startTwoFactorSetup())
        } catch is CancellationError {
            setup = .idle
        } catch {
            setup = .failed(error.asAPIError)
        }
    }

    private func verify() async {
        guard code.count == 6, !isVerifying else { return }
        isVerifying = true
        error = nil
        defer { isVerifying = false }
        do {
            recoveryCodes = try await model.verifyTwoFactor(code: code)
            Haptics.success()
        } catch let apiError as APIError {
            switch apiError {
            case .rejected: error = String(localized: "Invalid code — check your authenticator app")
            default: error = apiError.localizedDescription
            }
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

// MARK: - Disable and regenerate

/// Both need the account password. Disabling is destructive; regenerating
/// replaces the old recovery codes with 10 new ones, shown once.
struct TwoFactorPasswordView: View {
    enum Purpose { case disable, regenerate }

    let model: AccountSettingsModel
    let purpose: Purpose

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String? = nil
    @State private var isWorking = false
    @State private var recoveryCodes: [String]? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let recoveryCodes {
                    ScrollView {
                        RecoveryCodesPanel(codes: recoveryCodes,
                                           lead: String(localized: "Your old recovery codes no longer work."))
                            .padding(StudioSpace.s6)
                            .readableWidth(.sheet)
                    }
                    .background(Color.studioBg)
                } else {
                    Form {
                        Section {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .onSubmit { Task { await submit() } }
                        } header: {
                            Text(purpose == .disable
                                 ? "Enter your password to confirm disabling 2FA."
                                 : "Enter your password to replace your recovery codes.")
                        } footer: {
                            FormErrorText(message: error)
                        }
                        .studioRowBackground()
                        Section {
                            Button(role: purpose == .disable ? .destructive : nil) {
                                Task { await submit() }
                            } label: {
                                HStack {
                                    Text(purpose == .disable ? "Disable 2FA" : "Generate New Codes")
                                    Spacer()
                                    if isWorking { ProgressView() }
                                }
                            }
                            .disabled(password.isEmpty || isWorking)
                        }
                        .studioRowBackground()
                    }
                    .studioForm()
                }
            }
            .navigationTitle(purpose == .disable ? "Disable 2FA" : "Recovery Codes")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if recoveryCodes != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .interactiveDismissDisabled(recoveryCodes != nil || isWorking)
        }
        .cardsiteSheet(.form)
    }

    private func submit() async {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            switch purpose {
            case .disable:
                try await model.disableTwoFactor(password: password)
                Haptics.success()
                dismiss()
            case .regenerate:
                recoveryCodes = try await model.regenerateRecoveryCodes(password: password)
                Haptics.success()
            }
        } catch {
            self.error = error.asAPIError.localizedDescription
        }
    }
}

// MARK: - Recovery codes

/// Codes shown once, with copy and save. Each works one time in place of an
/// authenticator code.
struct RecoveryCodesPanel: View {
    let codes: [String]
    let lead: String

    @State private var isExporting = false
    @State private var saveError: String? = nil

    private var text: String { codes.joined(separator: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            StudioBanner(
                lead: lead,
                message: String(localized: "Save these recovery codes somewhere safe. Each one signs you in once if you lose your authenticator. They won’t be shown again."),
                tone: .success
            )

            StudioCard {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: StudioSpace.s3)],
                          alignment: .leading, spacing: StudioSpace.s3) {
                    ForEach(Array(codes.enumerated()), id: \.offset) { _, code in
                        Text(verbatim: code)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Recovery codes"))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: StudioSpace.s2) { actions }
                VStack(alignment: .leading, spacing: StudioSpace.s2) { actions }
            }

            if let saveError {
                FormErrorText(message: saveError)
            }
        }
        .fileExporter(isPresented: $isExporting,
                      item: RecoveryCodesFile(text: text),
                      contentTypes: [.plainText],
                      defaultFilename: String(localized: "Cardsite recovery codes")) { result in
            if case .failure(let error) = result {
                saveError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        StudioButton(String(localized: "Copy All"), systemImage: "doc.on.doc", variant: .outline) {
            Pasteboard.copy(text)
            Haptics.success()
        }
        StudioButton(String(localized: "Save…"), systemImage: "square.and.arrow.down", variant: .outline) {
            isExporting = true
        }
    }
}

/// The codes as a plain-text file for the exporter.
struct RecoveryCodesFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
    }
}

// MARK: - QR

/// A QR code drawn on the device with Core Image, so the TOTP secret is
/// never sent anywhere to be rendered.
struct ProvisioningQRCode: View {
    let payload: String

    var body: some View {
        if let image = Self.render(payload) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: StudioSpace.s16 * 3, maxHeight: StudioSpace.s16 * 3)
                .padding(StudioSpace.s3)
                // Black on white in both appearances: authenticators expect it.
                .background(RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous).fill(Color.StudioPalette.neutral0))
                .accessibilityElement()
                .accessibilityLabel(Text("QR code for your authenticator app"))
                .accessibilityAddTraits(.isImage)
        } else {
            Text("The QR code couldn’t be drawn. Enter the key by hand instead.")
                .studioText(.uiSm)
                .studioMuted()
        }
    }

    static func render(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

// MARK: - Small pieces

/// An icon button that copies a value and confirms with a check.
struct SecretCopyButton: View {
    let value: String
    let label: String
    @State private var didCopy = false

    var body: some View {
        Button {
            Pasteboard.copy(value)
            Haptics.success()
            didCopy = true
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(label))
        .accessibilityValue(didCopy ? Text("Copied") : Text(""))
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

private extension String {
    /// "ABCD EFGH IJKL" for reading a long key aloud or by eye.
    func chunked(by size: Int) -> String {
        guard size > 0 else { return self }
        var out = ""
        for (index, character) in enumerated() {
            if index > 0, index % size == 0 { out.append(" ") }
            out.append(character)
        }
        return out
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

#if DEBUG
#Preview("Recovery codes") {
    ScrollView {
        RecoveryCodesPanel(
            codes: ["4f9k-2m7q", "x8c1-p0zr", "h3nv-6t2w", "q7ry-b5je", "m2ds-k9fa",
                    "z6uw-c1lp", "t4gx-8hbn", "w9ea-r3vm", "j5kq-y7os", "n1pt-d6ic"],
            lead: "Two-factor authentication is on."
        )
        .padding(StudioSpace.s6)
    }
    .background(Color.studioBg)
}

#Preview("Provisioning QR") {
    ProvisioningQRCode(payload: "otpauth://totp/Cardsite:ada@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Cardsite")
        .padding(StudioSpace.s6)
}
#endif
