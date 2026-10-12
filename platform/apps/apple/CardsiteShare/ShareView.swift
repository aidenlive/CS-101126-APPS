import SwiftUI
import StudioKit
import CardsiteKit

/// Shorten from any app: the shared address, an optional custom address,
/// then the short link with Copy.
struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.studioBg.ignoresSafeArea())
                .navigationTitle("Shorten with Cardsite")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .reading:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Loading")
        case .signedOut:
            signedOut
        case .noLink:
            ScrollView {
                StudioEmptyState(
                    systemImage: "link",
                    title: String(localized: "No link to shorten"),
                    message: String(localized: "Share a web page, or text with a web address in it.")
                ) {
                    StudioButton(String(localized: "Done"), variant: .outline) { model.onComplete() }
                }
                .padding(StudioSpace.s6)
            }
        case .editing:
            form
        case .created(let url, let address):
            created(url: url, address: address)
        }
    }

    // MARK: Signed out

    private var signedOut: some View {
        ScrollView {
            StudioEmptyState(
                systemImage: "person.crop.circle.badge.exclamationmark",
                title: String(localized: "Sign in to Cardsite first"),
                message: model.couldNotOpenApp
                    ? String(localized: "Open Cardsite from your Home Screen, sign in, then share the link again.")
                    : String(localized: "Sign in to Cardsite, then share the link again.")
            ) {
                StudioButton(String(localized: "Open Cardsite"), systemImage: "arrow.up.forward.app", variant: .primary) {
                    Task { await model.openCardsite() }
                }
            }
            .padding(StudioSpace.s6)
        }
    }

    // MARK: Editing

    private var form: some View {
        Form {
            Section("Destination") {
                if let destination = model.destination {
                    Label {
                        Text(verbatim: destination.absoluteString)
                            .studioText(.ui)
                            .foregroundStyle(Color.studioText)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(Color.studioAccentLine)
                    }
                }
            }

            Section {
                Toggle("Custom address", isOn: $model.usesCustomAddress)
                if model.usesCustomAddress {
                    HStack(spacing: 0) {
                        Text(verbatim: "\(model.publicHost)/")
                            .studioText(.ui)
                            .foregroundStyle(Color.studioText3)
                            .accessibilityHidden(true)
                        TextField("your-address", text: $model.slug)
                            .studioText(.ui)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .accessibilityLabel("Custom address")
                            .onSubmit { Task { await model.shorten() } }
                    }
                }
            } header: {
                Text("Short link")
            } footer: {
                if let slugError = model.slugError {
                    Label(slugError, systemImage: "exclamationmark.circle.fill")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioError)
                } else {
                    Text(model.usesCustomAddress
                         ? String(localized: "Letters, numbers, hyphens and underscores.")
                         : String(localized: "Cardsite picks a short random address."))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }

            if let message = model.errorMessage {
                Section {
                    StudioBanner(lead: String(localized: "Couldn't shorten this."), message: message, tone: .error)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .disabled(model.isCreating)
    }

    // MARK: Created

    private func created(url: URL, address: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpace.s6) {
                StudioCard {
                    VStack(alignment: .leading, spacing: StudioSpace.s3) {
                        StudioKicker(String(localized: "Short link ready"))
                        Text(verbatim: address)
                            .studioText(.titleSm)
                            .foregroundStyle(Color.studioText)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text(verbatim: url.absoluteString))
                        if let destination = model.destination {
                            Label {
                                Text(verbatim: destination.absoluteString)
                                    .studioText(.uiSm)
                                    .foregroundStyle(Color.studioText2)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: "arrow.turn.down.right")
                                    .foregroundStyle(Color.studioText3)
                            }
                            .accessibilityLabel(Text("Opens \(destination.absoluteString)"))
                        }
                    }
                }
                HStack(spacing: StudioSpace.s3) {
                    StudioButton(model.didCopy ? String(localized: "Copied") : String(localized: "Copy"),
                                 systemImage: model.didCopy ? "checkmark" : "doc.on.doc",
                                 variant: .primary) {
                        model.copyLink()
                    }
                    StudioButton(String(localized: "Done"), variant: .outline) { model.onComplete() }
                }
            }
            .padding(StudioSpace.s6)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch model.phase {
        case .editing:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { model.onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isCreating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Shortening")
                } else {
                    Button("Shorten") { Task { await model.shorten() } }
                }
            }
        case .reading, .signedOut, .noLink:
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { model.onCancel() }
            }
        case .created:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { model.onComplete() }
            }
        }
    }
}

#if DEBUG
#Preview("Editing") {
    ShareView(model: .preview(.editing))
        .onAppear { StudioFonts.register() }
}

#Preview("Created") {
    ShareView(model: .preview(.created(url: URL(string: "https://card.site/k7m2p9x")!, address: "card.site/k7m2p9x")))
        .onAppear { StudioFonts.register() }
}

#Preview("Signed out") {
    ShareView(model: .preview(.signedOut))
        .onAppear { StudioFonts.register() }
}

#Preview("No link") {
    ShareView(model: .preview(.noLink, destination: nil))
        .onAppear { StudioFonts.register() }
}
#endif
