import SwiftUI
import StudioKit
import CardsiteKit

/// Creates a QR code for one of the user's short links (dynamic: its
/// destination can change after printing) or for any web address.
struct QRCodeEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(QRCodesModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var onCreated: (QRCode) -> Void

    enum Source: Hashable { case link, url }

    @State private var source: Source = .link
    @State private var name = ""
    @State private var urlText = ""
    @State private var links: Loadable<[Resource]> = .idle
    @State private var selectedLinkID: Int?
    @State private var nameError: String?
    @State private var urlError: String?
    @State private var formError: String?
    @State private var isSaving = false

    init(onCreated: @escaping (QRCode) -> Void = { _ in }) {
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioSpace.s5) {
                    StudioTextField(String(localized: "Name"), text: $name,
                                    placeholder: String(localized: "Window menu"),
                                    help: String(localized: "Only you see this."),
                                    errorMessage: nameError)

                    Picker("Encodes", selection: $source) {
                        Text("One of my links").tag(Source.link)
                        Text("Any web address").tag(Source.url)
                    }
                    .pickerStyle(.segmented)

                    switch source {
                    case .link: linkPicker
                    case .url:
                        StudioTextField(String(localized: "Web address"), text: $urlText,
                                        placeholder: "example.com/menu",
                                        help: String(localized: "Fixed once printed. To change it later, use one of your links instead."),
                                        errorMessage: urlError)
                            .plainEntry()
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            #endif
                    }

                    FormErrorText(message: formError)
                }
                .padding(StudioSpace.s6)
                .readableWidth(560)
            }
            .background(Color.studioBg)
            .navigationTitle("New QR Code")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Create") { Task { await save() } } }
                }
            }
            .task { await loadLinks() }
            .onChange(of: source) { urlError = nil; formError = nil }
            .interactiveDismissDisabled(isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    @ViewBuilder
    private var linkPicker: some View {
        switch links {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        case .failed(let error):
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text(error.localizedDescription).studioText(.uiSm).studioMuted()
                StudioButton(String(localized: "Try Again"), systemImage: "arrow.clockwise", variant: .outline) {
                    Task { await loadLinks() }
                }
            }
        case .loaded(let items) where items.isEmpty:
            StudioBanner(lead: String(localized: "No links yet."),
                         message: String(localized: "Create a short link first, or encode any web address."),
                         tone: .info)
        case .loaded(let items):
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text("Link").studioText(.uiSm)
                Picker("Link", selection: $selectedLinkID) {
                    Text("Choose a link").tag(Int?.none)
                    ForEach(items) { link in
                        Text(verbatim: app.addresses.display(for: link.slug)).tag(Int?.some(link.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text("Change the link's destination any time; printed codes follow it.")
                    .studioText(.uiSm).studioMuted()
                if let urlError { Text(urlError).studioText(.uiSm).foregroundStyle(Color.studioError) }
            }
        }
    }

    private func loadLinks() async {
        guard links.value == nil else { return }
        links = .loading
        do {
            let page = try await model.client.links()
            let items = page.items.filter { !$0.isBioPage }
            links = .loaded(items)
            if selectedLinkID == nil { selectedLinkID = items.first?.id }
            if items.isEmpty { source = .url }
        } catch {
            links = .failed(error.asAPIError)
        }
    }

    private func save() async {
        guard !isSaving else { return }
        nameError = nil
        urlError = nil
        formError = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var target: URL?
        var linkID: Int?
        switch source {
        case .link:
            if let id = selectedLinkID, let link = links.value?.first(where: { $0.id == id }) {
                target = app.addresses.url(for: link.slug)
                linkID = link.id
            } else {
                urlError = String(localized: "Choose a link.")
            }
        case .url:
            target = Destination.normalized(urlText)
            if target == nil {
                urlError = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
            }
        }
        if trimmedName.isEmpty {
            nameError = String(localized: "Give the code a name.")
        }
        guard let target, !trimmedName.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        do {
            let code = try await model.create(name: trimmedName, url: target, linkID: linkID)
            Haptics.success()
            onCreated(code)
            dismiss()
        } catch {
            formError = error.asAPIError.localizedDescription
        }
    }
}
