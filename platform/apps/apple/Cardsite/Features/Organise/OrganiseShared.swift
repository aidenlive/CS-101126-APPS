import SwiftUI
import StudioKit
import CardsiteKit

/*
 Pieces the three Organise screens share: the project colour dot and
 palette, the confirm-and-report delete flow, and preview data.

 The screens (ProjectsView, DomainsView, PixelsView) are `.more`
 destinations: stack-free content the shell wraps in a NavigationStack on
 iPad and Mac and pushes onto More on iPhone. Their create and edit sheets
 bring their own stacks, which is fine: a sheet is a new presentation.

 Accessibility identifiers, for CardsiteUITests (the registry's
 DestinationView stamps `screen.<destination>` on each root):
   org.<kind>.row.<n>     row n, 0 at the top
   org.<kind>.create      the toolbar's New button
   org.<kind>.editor.*    the editor's fields and save button
   org.domains.verify     Verify on a domain's page and after adding one
 where <kind> is projects, domains or pixels.
 */

// MARK: - Project colour

/// A project's colour, from the hex the user chose. These colours are the
/// user's data, not design tokens; a missing or unreadable one draws in
/// the faint text ink, as the web does.
struct ProjectColorDot: View {
    let hex: String
    var size: CGFloat = StudioSpace.s3

    var body: some View {
        Circle()
            .fill(HexColor.color(from: hex) ?? Color.studioText3)
            .overlay(Circle().strokeBorder(Color.studioBorder, lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum ProjectPalette {
    /// Quick picks: the Studio chart palette and the accent, resolved to the
    /// hex the server stores. The colour well covers everything else.
    static var presets: [String] {
        var seen = Set<String>()
        return [Color.studioAccent, .studioViz1, .studioViz2, .studioViz3, .studioViz4, .studioViz5, .studioViz6]
            .map { HexColor.hex(from: $0) }
            .filter { seen.insert($0).inserted }
    }

    /// A new project's colour: the accent, as the web's default lime.
    static var defaultHex: String { HexColor.hex(from: Color.studioAccent) }
}

// MARK: - Rows

/// "Added 12 Oct 2026", the web's `pixels.added`.
func organiseAddedLine(_ date: Date?) -> String? {
    date.map { String(localized: "Added \($0.formatted(date: .abbreviated, time: .omitted))") }
}

/// A "load more" row that fetches the next page when it appears.
struct OrganiseLoadMoreRow<Item: Identifiable & Sendable & Equatable>: View {
    let list: PagedListModel<Item>

    var body: some View {
        if list.hasMore {
            HStack {
                Spacer()
                ProgressView()
                    .accessibilityLabel(Text("Loading more"))
                Spacer()
            }
            .studioClearRow()
            .task(id: list.items.count) { [list] in await list.loadMore() }
        }
    }
}

// MARK: - Delete

/// The confirm dialog and failure alert every Organise list uses, so a
/// delete always asks first and always says why it failed.
struct OrganiseDeleteFlow<Item: Identifiable & Sendable>: ViewModifier {
    @Binding var pending: Item?
    let title: String
    let confirmTitle: (Item) -> String
    let message: String
    let delete: @MainActor (Item) async throws -> Void

    @State private var failure: String? = nil

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title,
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible,
                presenting: pending
            ) { item in
                Button(confirmTitle(item), role: .destructive) {
                    Task { await run(item) }
                }
            } message: { _ in
                Text(message)
            }
            .alert(String(localized: "Couldn’t delete"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private func run(_ item: Item) async {
        do {
            try await delete(item)
            Haptics.success()
        } catch {
            failure = error.asAPIError.localizedDescription
        }
        pending = nil
    }
}

extension View {
    func organiseDeleteFlow<Item: Identifiable & Sendable>(
        _ pending: Binding<Item?>,
        title: String,
        confirmTitle: @escaping (Item) -> String,
        message: String,
        delete: @escaping @MainActor (Item) async throws -> Void
    ) -> some View {
        modifier(OrganiseDeleteFlow(pending: pending, title: title, confirmTitle: confirmTitle, message: message, delete: delete))
    }
}

// MARK: - Preview data

#if DEBUG
enum OrganisePreviewData {
    static let projects: [Project] = [
        Project(id: 4, workspaceID: 234, name: "Clients", color: ProjectPalette.presets.dropFirst(2).first ?? "",
                createdAt: .now.addingTimeInterval(-5_184_000)),
        Project(id: 3, workspaceID: 234, name: "Launch week", color: ProjectPalette.defaultHex,
                createdAt: .now.addingTimeInterval(-864_000)),
        Project(id: 2, workspaceID: 234, name: "Archive", color: "", createdAt: .now.addingTimeInterval(-9_000_000)),
    ]

    static let domains: [CustomDomain] = [
        CustomDomain(id: 4, workspaceID: 234, scheme: "https", host: "go.avery.example",
                     createdAt: .now.addingTimeInterval(-345_600)),
        CustomDomain(id: 3, workspaceID: 234, scheme: "https://", host: "links.northwind.example",
                     customNotFoundURL: "https://northwind.example/404", sslIsEnabled: true, forceSSL: true,
                     redirectType: DomainRedirectType.temporary.rawValue, isVerified: true,
                     lastVerifiedAt: .now.addingTimeInterval(-7_200), createdAt: .now.addingTimeInterval(-8_640_000)),
    ]

    static let pixelTypes: [PixelType] = [
        PixelType(key: "facebook", name: "Facebook Pixel", description: "Meta Ads conversion tracking",
                  fieldLabel: "Pixel ID", emitsBeacon: true),
        PixelType(key: "google_analytics", name: "Google Analytics", description: "Google Analytics (UA / GA4)",
                  fieldLabel: "Tracking ID", emitsBeacon: false),
        PixelType(key: "linkedin", name: "LinkedIn Insight Tag", description: "LinkedIn conversion tracking",
                  fieldLabel: "Partner ID", emitsBeacon: true),
    ]

    static let pixels: [TrackingPixel] = [
        TrackingPixel(id: 4, workspaceID: 234, type: "google_analytics", name: "Site analytics", pixel: "G-FIXTURE01",
                      createdAt: .now.addingTimeInterval(-3_456_000)),
        TrackingPixel(id: 3, workspaceID: 234, type: "facebook", name: "Meta ads", pixel: "1234567890",
                      createdAt: .now.addingTimeInterval(-6_912_000)),
    ]

    static var client: APIClient { APIClient(baseURL: AppConfiguration.preview.apiBaseURL) }
}
#endif
