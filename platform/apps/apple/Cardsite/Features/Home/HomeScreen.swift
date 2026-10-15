import SwiftUI
import StudioKit
import CardsiteKit

/// Home: the web dashboard (DashboardPage.tsx) as a native page.
///
/// A greeting with the workspace's headline figures, quick create (paste a
/// URL, or pick a type), 30 days of traffic with the top performer, and the
/// recently edited resources. One column on iPhone, where the stat cards
/// and create tiles become snapping shelves, and two or three on iPad and
/// Mac, decided by the width the page actually has.
///
/// The toolbar is the shell's: the bell (Inbox, badged) and the `+` create
/// menu in one group, the account avatar alone at the trailing edge. Search
/// is its own tab; on iPad and Mac the toolbar also opens the ⌘K palette.
/// The bars are the system's (glass on OS 26); Home paints no bar
/// background of its own.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(HomeModel.self) private var model
    @Environment(ShellRouter.self) private var router
    @Environment(\.studioViewport) private var viewport

    var body: some View {
        NavigationStack {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AppDestination.home.screenIdentifier)
                .navigationTitle("Home")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .shellSubtitle(app.currentWorkspace?.name)
                .toolbar { toolbar }
                .navigationDestination(for: Resource.self) { link in
                    LinkDetailView(link: link)
                }
                // The bell pushes the Inbox here.
                .navigationDestination(for: AppDestination.self) { destination in
                    DestinationView(destination: destination)
                }
        }
        .task { [model] in await model.loadIfNeeded() }
    }

    private var content: some View {
        ScrollView {
            HomeDashboard(model: model)
                .padding(.horizontal, viewport.contentPadding)
                .padding(.top, StudioSpace.s6)
                .padding(.bottom, StudioSpace.s12)
                .readableWidth(.dashboard)
        }
        .background(Color.studioBg)
        .platformScrollEdge()
        .refreshable { [model] in await model.refresh() }
    }

    /// At most two groups: [search · bell · +] and the avatar on its own.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { [model] in await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRefreshing)
            .help("Refresh (⌘R)")
        }
        #endif
        ToolbarItemGroup(placement: .primaryAction) {
            if !router.isCompact {
                Button {
                    router.togglePalette()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Search pages, actions and links (⌘K)")
            }
            #if !os(macOS)
            InboxBellLink()
            #endif
            CreateMenu()
        }
        #if !os(macOS)
        AccountToolbarItem()
        #endif
    }
}

enum HomeLayout {
    /// Columns for a content width, from the same breakpoints the Studio
    /// viewport uses, and never more than one at accessibility text sizes.
    static func columns(for width: CGFloat, typeSize: DynamicTypeSize) -> Int {
        if typeSize.isAccessibilitySize { return width >= StudioLayout.bpDesktop ? 2 : 1 }
        if width >= StudioLayout.bpDesktop * 0.8 { return 3 }
        if width >= StudioLayout.bpTablet * 0.8 { return 2 }
        return 1
    }
}

/// The page body. Separate from the screen so previews and the loading
/// skeleton can render it without the navigation chrome.
struct HomeDashboard: View {
    let model: HomeModel

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.studioViewport) private var viewport
    @State private var width: CGFloat = 0

    private var columns: Int { HomeLayout.columns(for: width, typeSize: typeSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: viewport.sectionGap) {
            HomeGreeting(summary: model.snapshot?.summary)

            if let error = model.refreshError {
                RefreshErrorBanner(error: error) { model.dismissRefreshError() }
            }

            HomeCreateSection(columns: columns)

            switch model.state {
            case .idle, .loading:
                // The skeleton: the real layout, redacted, so nothing jumps
                // when the data lands.
                VStack(alignment: .leading, spacing: viewport.sectionGap) {
                    dataSections(.sample)
                }
                .redacted(reason: .placeholder)
                .disabled(true)
                .loadingAccessibility(true)
            case .failed(let error):
                StudioCard {
                    InlineErrorState(error: error) { [model] in await model.refresh() }
                }
            case .loaded(let snapshot):
                dataSections(snapshot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }

    @ViewBuilder
    private func dataSections(_ snapshot: HomeModel.Snapshot) -> some View {
        HomeStatsSection(snapshot: snapshot, columns: columns)
        HomeRecentsSection(recent: snapshot.recent)
    }
}

#if DEBUG
private struct HomePreview: View {
    @State private var app: AppModel
    @State private var home: HomeModel
    @State private var links: LinksModel
    @State private var inbox: InboxModel
    @State private var router: ShellRouter

    init(state: Loadable<HomeModel.Snapshot>, compact: Bool) {
        let app = AppModel.preview()
        let router = ShellRouter()
        router.adapt(isCompact: compact)
        _app = State(initialValue: app)
        _home = State(initialValue: HomeModel(client: app.client, state: state))
        _links = State(initialValue: LinksModel(client: app.client))
        _inbox = State(initialValue: InboxModel(client: app.client))
        _router = State(initialValue: router)
    }

    var body: some View {
        HomeScreen()
            .environment(app)
            .environment(home)
            .environment(links)
            .environment(inbox)
            .environment(router)
            .studioViewport()
    }
}

#Preview("Home") {
    HomePreview(state: .loaded(.sample), compact: false)
}

#Preview("Home, iPhone") {
    HomePreview(state: .loaded(.sample), compact: true)
}

#Preview("Empty workspace") {
    HomePreview(state: .loaded(.empty), compact: true)
}

#Preview("Loading") {
    HomePreview(state: .loading, compact: true)
}

#Preview("Offline") {
    HomePreview(state: .failed(.offline), compact: true)
}

#Preview("Error") {
    HomePreview(state: .failed(.server(status: 500, title: nil)), compact: false)
}
#endif
