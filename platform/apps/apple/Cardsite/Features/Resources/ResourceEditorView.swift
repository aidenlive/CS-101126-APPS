import SwiftUI
import StudioKit
import CardsiteKit

/// The editor for any kind: pushed from a list for a saved resource, or the
/// root of a create sheet (item nil). Stack-free: its container brings the
/// navigation stack.
struct ResourceEditorView: View {
    let kind: ResourceKind
    let item: ResourceItem?
    let list: ResourceListModel
    var onCreated: (ResourceItem) -> Void

    init(kind: ResourceKind, item: ResourceItem?, list: ResourceListModel,
         onCreated: @escaping (ResourceItem) -> Void = { _ in }) {
        self.kind = kind
        self.item = item
        self.list = list
        self.onCreated = onCreated
    }

    var body: some View {
        switch kind {
        case .vcard:
            VCardEditorView(item: item, list: list, onCreated: onCreated)
        case .event:
            EventEditorView(item: item, list: list, onCreated: onCreated)
        case .paymentLink:
            PaymentLinkEditorView(item: item, list: list, onCreated: onCreated)
        case .file:
            FileLinkEditorView(item: item, list: list, onCreated: onCreated)
        case .staticPage:
            StaticPageEditorView(item: item, list: list, onCreated: onCreated)
        case .splash:
            SplashPageEditorView(item: item, list: list, onCreated: onCreated)
        }
    }
}

/// The create sheet for the New menu, ⌘-shortcuts, the palette and Home:
/// `app.composer` opens it with a kind. It has its own list model (for the
/// domain picker and the save path); once something is created it tells the
/// list on screen through `.resourceCreated`, then `onCreated` runs (the
/// shell opens the kind's list).
struct ResourceComposerSheet: View {
    @Environment(AppModel.self) private var app
    let kind: ResourceKind
    var onCreated: (ResourceItem) -> Void = { _ in }

    @State private var list: ResourceListModel? = nil

    var body: some View {
        NavigationStack {
            if let list {
                ResourceEditorView(kind: kind, item: nil, list: list) { item in
                    NotificationCenter.default.post(name: .resourceCreated, object: kind.rawValue)
                    onCreated(item)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.studioBg)
                    .accessibilityLabel(Text("Loading"))
            }
        }
        .task {
            guard list == nil else { return }
            let model = ResourceListModel(kind: kind, client: app.client)
            model.onError = { [app] error in app.handle(error) }
            list = model
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
}

// MARK: - Preview data

extension ManagedResource {
    /// Fixture 25b.
    static let previewVCard = ManagedResource(
        id: 25, workspaceID: 234, type: .vcard, slug: "ncv-ada",
        settings: [
            "vcard_first_name": "Augusta", "vcard_last_name": "Lovelace", "vcard_email": "ada@example.test",
            "vcard_company": "Engines", "vcard_job_title": "Analyst", "vcard_url": "https://example.com",
            "vcard_city": "London", "vcard_country": "United Kingdom", "vcard_birthday": "1815-12-10",
            "vcard_phone_numbers": [["value": "+44 20 7946 0000"]],
            "vcard_socials": [["label": "Site", "value": "https://example.com"]],
            "vcard_note": "", "vcard_street": "", "vcard_zip": "", "vcard_region": "",
        ],
        clicks: 128
    )

    /// Fixture 25f.
    static let previewEvent = ManagedResource(
        id: 26, workspaceID: 234, type: .event, slug: "launch-night",
        settings: [
            "event_name": "Launch night", "event_location": "Manchester", "event_note": "Drinks",
            "event_url": "https://example.com/e", "event_start_datetime": "2030-11-20T18:00",
            "event_end_datetime": "2030-11-20T21:00", "event_timezone": "Europe/London",
            "event_first_alert_datetime": "", "event_second_alert_datetime": "",
            "expiration_url": "", "sensitive_content": false,
        ],
        clicks: 42
    )

    /// Fixture 25l.
    static let previewPaymentLink = ManagedResource(
        id: 27, workspaceID: 234, type: .paymentLink, slug: "tip-jar",
        destination: "https://buy.example.com/checkout/123", settings: ["title": "Tip jar"],
        clicks: 9, isEnabled: false
    )

    /// Fixture 25o.
    static let previewFile = ManagedResource(
        id: 28, workspaceID: 234, type: .file, slug: "brochure",
        settings: ["file": "brochure.pdf", "file_path": "documents/2026/10/12/94c1.pdf",
                   "force_download_is_enabled": true, "sensitive_content": false],
        clicks: 311
    )

    /// Fixture 25q.
    static let previewStatic = ManagedResource(
        id: 29, workspaceID: 234, type: .staticPage, slug: "launch-site",
        settings: ["file_path": "documents/2026/10/12/be63.zip", "static_folder": "be63",
                   "static_kind": "zip", "sensitive_content": false],
        clicks: 57
    )
}

extension SplashPage {
    /// Fixture 21j.
    static let preview = SplashPage(id: 3, workspaceID: 234, name: "Wait", title: "One moment",
                                    description: "Taking you there", linkUnlockSeconds: 5, autoRedirect: true,
                                    settings: ["secondary_button_name": "Skip", "ads_header": "<script></script>"])
}

extension ResourceListModel {
    /// A list model holding sample rows, with a domain and every capability.
    static func preview(_ kind: ResourceKind, items: [ResourceItem], client: APIClient) -> ResourceListModel {
        let options = ResourceOptionsModel(client: client, targeting: nil,
                                           domains: [DomainOption(id: 3, host: "go.example.com")])
        let model = ResourceListModel(kind: kind, client: client, options: options)
        for item in items.reversed() { model.list.insert(item) }
        return model
    }
}
