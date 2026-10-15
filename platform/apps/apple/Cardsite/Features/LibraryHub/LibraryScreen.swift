import SwiftUI
import StudioKit
import CardsiteKit

/// The Library tab: the root of everything that isn't Home or Links on
/// iPhone (and in iPad's tab-bar mode).
///
/// Its stack is the router's `libraryPath`, so `ShellRouter.open(_:)` can
/// push any sidebar-only destination here: hub rows, search results, the
/// palette, deep links and the UI tests' `-CardsiteOpen` all land the same
/// way. On iPad and Mac the sidebar lists every destination itself, so the
/// hub isn't in the sidebar.
struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(LibraryModel.self) private var model
    @Environment(ShellRouter.self) private var router

    var body: some View {
        @Bindable var nav = router
        NavigationStack(path: $nav.libraryPath) {
            LibraryHub(model: model)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("screen.library")
                .pageHeadNavigationTitle(String(localized: "Library"))
                .shellSubtitle(app.currentWorkspace?.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        CreateMenu()
                    }
                }
                .accountToolbarItem()
                .navigationDestination(for: AppDestination.self) { destination in
                    DestinationView(destination: destination)
                }
                .navigationDestination(for: Resource.self) { link in
                    LinkDetailView(link: link)
                }
        }
        .task { [model] in await model.loadIfNeeded() }
    }
}

/// The hub's page: the two-tone head (its one focal element), Recently
/// edited, then the type rows, each under a quiet section header and
/// separated by Studio's section rhythm. Separate from the screen so
/// previews render it without the chrome.
struct LibraryHub: View {
    let model: LibraryModel
    @Environment(AppModel.self) private var app
    @Environment(\.studioViewport) private var viewport

    /// Studio's sanctioned section break, tighter on iPhone.
    private var sectionGap: CGFloat {
        viewport == .compact
            ? StudioComposition.rhythmSectionGapCompact
            : StudioComposition.rhythmSectionGap
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                // The banner belongs to the head, not a section of its own.
                VStack(alignment: .leading, spacing: StudioSpace.s5) {
                    StudioPageHead(
                        kicker: kicker,
                        title: String(localized: "Your "),
                        accent: String(localized: "library."),
                        description: String(localized: "Everything in this workspace, by type. Pick up a recent edit, or open a collection.")
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .studioEntrance()

                    if let error = model.refreshError {
                        RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                    }
                }

                LibraryRecentSection(model: model)
                    .studioEntrance(delay: 0.06)

                ForEach(LibraryGroup.allCases) { group in
                    LibraryGroupSection(group: group, summary: model.snapshot?.summary)
                }
            }
            .padding(.horizontal, viewport.contentPadding)
            // StudioScreen's insets.
            .padding(.top, StudioSpace.s4)
            .padding(.bottom, StudioSpace.s10)
            .readableWidth(.reading)
        }
        .background(Color.studioBg)
        .platformScrollEdge()
        .refreshable { [model] in await model.refresh() }
    }

    /// "Library · Northwind Studio" (the kicker style is uppercase).
    private var kicker: String {
        guard let name = app.currentWorkspace?.name, !name.isEmpty else { return String(localized: "Library") }
        return String(localized: "Library · \(name)")
    }
}

#if DEBUG
private struct LibraryPreview: View {
    @State private var app: AppModel
    @State private var model: LibraryModel
    @State private var router = ShellRouter()
    @State private var inbox: InboxModel

    init(state: Loadable<LibraryModel.Snapshot>) {
        let app = AppModel.preview()
        _app = State(initialValue: app)
        _model = State(initialValue: LibraryModel(client: app.client, state: state))
        _inbox = State(initialValue: InboxModel(client: app.client))
    }

    var body: some View {
        LibraryScreen()
            .environment(app)
            .environment(model)
            .environment(router)
            .environment(inbox)
            .environment(PagesModel(client: app.client))
            .studioViewport()
    }
}

#Preview("Library") {
    LibraryPreview(state: .loaded(.sample))
}

#Preview("Empty workspace") {
    LibraryPreview(state: .loaded(.empty))
}

#Preview("Loading") {
    LibraryPreview(state: .loading)
}

#Preview("Offline") {
    LibraryPreview(state: .failed(.offline))
}

#Preview("Error") {
    LibraryPreview(state: .failed(.server(status: 500, title: nil)))
}
#endif
