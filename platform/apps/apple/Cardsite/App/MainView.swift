import SwiftUI
import StudioKit
import CardsiteKit
#if os(iOS)
import UIKit
#endif

/// The signed-in app, built from the navigation registry.
///
/// One sidebar-adaptable `TabView` serves every width, following Apple's
/// own pattern for changing tab structure between size classes:
///
/// · iPhone (and compact-width iPad windows): a tab bar of exactly Home,
///   Links and Library, plus the Search tab, which the system splits off
///   as the trailing circle. Library is the hub for everything else, and
///   the avatar on Home and Library opens the account sheet.
/// · iPad and Mac: a sidebar in sections (Overview, Content, Organize,
///   Account) holding every destination, under the workspace switcher.
///   Search is the sidebar's search field.
///
/// The two are separate tab views chosen by size class (`tabs`). No tab
/// uses `.hidden(_:)`: with the iOS 27 SDK a selection that points at a
/// removed tab can crash, so the router keeps the selection valid for the
/// tab view on screen.
///
/// A `NavigationSplitView` shell was the alternative. It was rejected
/// because Links and Pages are themselves split views (list and detail),
/// and SwiftUI doesn't support nesting split views; the tab view gives each
/// destination its own container and the system draws the sidebar, the
/// tab bar and the Liquid Glass chrome on OS 26.
///
/// The list models live here, not in the screens, so an item created from a
/// menu command appears in its list straight away and switching tabs does
/// not refetch. `RootView` rebuilds this view when the workspace changes,
/// which resets all of them to the new scope.
struct MainView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("main.tab") private var storedTab = AppDestination.home.rawValue

    @State private var router = ShellRouter()
    @State private var links: LinksModel
    @State private var qrCodes: QRCodesModel
    @State private var pages: PagesModel
    @State private var home: HomeModel
    @State private var library: LibraryModel
    @State private var search: QuickSearchModel
    /// One for the session, so the badge and the Inbox list agree.
    @State private var inbox: InboxModel
    /// Success feedback for every screen (`\.toasts`).
    @StateObject private var toasts = StudioToastCenter()

    init(client: APIClient) {
        _links = State(initialValue: LinksModel(client: client))
        _qrCodes = State(initialValue: QRCodesModel(client: client))
        _pages = State(initialValue: PagesModel(client: client))
        _home = State(initialValue: HomeModel(client: client))
        _library = State(initialValue: LibraryModel(client: client))
        _search = State(initialValue: QuickSearchModel(client: client))
        _inbox = State(initialValue: InboxModel(client: client))
    }

    /// iPhones always get the tab bar, even in landscape on the largest
    /// models, where the width class is regular.
    private var isCompact: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone || sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        presented
            .environment(router)
            .environment(links)
            .environment(qrCodes)
            .environment(pages)
            .environment(home)
            .environment(library)
            .environment(search)
            .environment(inbox)
            .studioToasts(toasts)
            .environment(\.toasts, toasts)
            // The Workspace screen calls this after creating, leaving or
            // deleting a workspace; the reload drops a workspace that is gone.
            .environment(\.switchWorkspace, SwitchWorkspaceAction { [model] id in
                await model.selectWorkspace(id)
                await model.loadWorkspaces()
            })
            .focusedSceneValue(\.shellRouter, router)
            .task { [model] in
                // After an offline launch the profile is a placeholder.
                if model.needsProfile { await model.refreshUser() }
                await model.loadWorkspaces()
            }
            .task { [inbox] in await inbox.pollUnreadCount() }
            .onAppear {
                links.onError = model.handle
                qrCodes.onError = model.handle
                pages.onError = model.handle
                home.onError = model.handle
                library.onError = model.handle
                search.onError = model.handle
                inbox.onError = model.handle
                router.tab = MainTab(storageKey: storedTab)
                router.adapt(isCompact: isCompact)
                #if DEBUG
                if let raw = FixtureMode.initialDestination, let destination = AppDestination(rawValue: raw) {
                    router.open(destination)
                }
                #endif
            }
            .onChange(of: isCompact) { _, compact in
                router.adapt(isCompact: compact)
            }
            .onChange(of: router.storageKey) { _, key in
                storedTab = key
            }
            .onChange(of: model.pendingDeepLink, initial: true) { _, link in
                guard let link else { return }
                model.pendingDeepLink = nil
                route(link)
            }
    }

    // The body is split into stages so the type checker handles each one
    // separately (one long chain timed out on Xcode 26).

    /// Two tab views, one per size class, as Apple recommends when the
    /// tab structure changes between them. CI showed that
    /// `defaultVisibility(.hidden, for: .tabBar)` alone doesn't trim an
    /// iPhone's tab bar (it applies to customizable tab views): every
    /// destination became a tab and the overflow went to a system More
    /// list, nesting each screen's stack inside More's.
    @ViewBuilder
    private var tabs: some View {
        #if os(iOS)
        if isCompact {
            compactTabs
        } else {
            sidebarTabs
        }
        #else
        sidebarTabs
        #endif
    }

    /// iPhone and compact iPad windows: exactly Home · Links · Library,
    /// and Search split off as the trailing circle. The router keeps the
    /// selection on one of these four (`adapt(isCompact:)`).
    #if os(iOS)
    private var compactTabs: some View {
        @Bindable var nav = router
        @Bindable var bindableSearch = search
        return TabView(selection: $nav.tab) {
            destinationTab(.home)
            destinationTab(.links)
            libraryTab
            searchTab
        }
        .searchable(text: $bindableSearch.query, prompt: Text("Pages, actions and links"))
        .minimizesTabBarOnScroll()
    }
    #endif

    /// iPad and Mac: every destination in the sidebar, in sections.
    private var sidebarTabs: some View {
        @Bindable var nav = router
        @Bindable var bindableSearch = search
        return TabView(selection: $nav.tab) {
            overviewTabs
            sectionTabs
            searchTab
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            WorkspaceSwitcher()
                .padding(.bottom, StudioSpace.s2)
        }
        // The Search tab takes the field: the sidebar's field on iPad and
        // Mac.
        .searchable(text: $bindableSearch.query, prompt: Text("Pages, actions and links"))
    }

    /// Home, Links, Pages, QR Codes and Statistics, with no section
    /// heading, as on the web. iPad's top tab bar (sidebar collapsed)
    /// keeps the iPhone's set: Home and Links, the selected item and
    /// Search. CI shows the regular-width tab bar honours these hints;
    /// the compact one doesn't, hence `compactTabs`.
    @TabContentBuilder<MainTab>
    private var overviewTabs: some TabContent<MainTab> {
        ForEach(AppDestination.Group.overview.destinations) { (destination: AppDestination) in
            destinationTab(destination)
                .defaultVisibility(destination.isInTabBar ? .automatic : .hidden, for: .tabBar)
        }
    }

    /// The hub for everything that isn't a tab on iPhone. The sidebar lists
    /// each destination itself, so the hub is only in the compact tab bar.
    #if os(iOS)
    @TabContentBuilder<MainTab>
    private var libraryTab: some TabContent<MainTab> {
        Tab(String(localized: "Library"), systemImage: "square.stack", value: MainTab.library) {
            LibraryScreen()
        }
    }
    #endif

    @TabContentBuilder<MainTab>
    private var searchTab: some TabContent<MainTab> {
        Tab(String(localized: "Search"), systemImage: "magnifyingglass", value: MainTab.search, role: .search) {
            SearchScreen()
        }
    }

    @TabContentBuilder<MainTab>
    private var sectionTabs: some TabContent<MainTab> {
        section(.content)
        section(.organise)
        section(.account)
    }

    /// One sidebar section. Sections are spelled out rather than built with
    /// a `ForEach` over groups: nested `ForEach` in a tab builder crashed
    /// the type checker on Xcode 26.
    private func section(_ group: AppDestination.Group) -> some TabContent<MainTab> {
        TabSection(group.title) {
            ForEach(group.destinations) { (destination: AppDestination) in
                destinationTab(destination)
            }
        }
        .defaultVisibility(.hidden, for: .tabBar)
    }

    private func destinationTab(_ destination: AppDestination) -> some TabContent<MainTab> {
        Tab(destination.title, systemImage: destination.systemImage, value: MainTab.destination(destination)) {
            DestinationRoot(destination: destination)
        }
        .badge(badgeCount(for: destination))
    }

    private var withPalette: some View {
        tabs
            .overlay {
                if router.isPalettePresented {
                    CommandPalette()
                        .transition(paletteTransition)
                        .zIndex(1)
                }
            }
            .animation(reduceMotion ? StudioAnimation.base : StudioAnimation.spring,
                       value: router.isPalettePresented)
    }

    private var paletteTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private var composerBinding: Binding<AppModel.Composer?> {
        Binding(get: { [router, model] in router.presentedLink == nil ? model.composer : nil },
                set: { [model] in model.composer = $0 })
    }

    private var presented: some View {
        @Bindable var nav = router
        @Bindable var app = model
        return withPalette
        .sheet(item: composerBinding) { composer in
            composerSheet(composer)
        }
        .sheet(isPresented: $nav.isAccountPresented) {
            AccountSheet()
        }
        .sheet(item: $nav.presentedLink) { link in
            PresentedLinkSheet(link: link) { router.presentedLink = nil }
            .sheet(item: $app.composer) { composer in
                composerSheet(composer)
            }
            .environment(links)
            .cardsiteSheet(.page)
        }
    }

    /// Routes a `cardsite://` link from a widget, the share extension or
    /// Siri (held by `RootView` until this shell is up).
    private func route(_ link: CardsiteDeepLink) {
        router.isPalettePresented = false
        switch link {
        case .home:
            router.open(.home)
        case .qrCode:
            router.open(.qrCodes)
        case .createLink(let destination):
            model.compose(.link, prefill: destination)
        case .link(let id):
            Task { [router, model] in
                do {
                    router.presentedLink = try await model.client.link(id: id)
                } catch is CancellationError {
                    // Cancelled: nothing to show.
                } catch {
                    // Deleted, or in another workspace: show the list.
                    model.handle(error)
                    router.open(.links)
                }
            }
        }
    }

    /// Something was created: Home's figures and recents, and Library's
    /// counts and shelf, catch up.
    private func refreshOverviews() {
        Task { [home] in await home.refresh() }
        Task { [library] in await library.refresh() }
    }

    /// The inbox's unread count on its sidebar item; zero hides the badge.
    private func badgeCount(for destination: AppDestination) -> Int {
        destination == .inbox ? inbox.unreadCount : 0
    }

    /// The create sheets. `composer.prefill` is Home's pasted URL for a
    /// short link, or a link's address for a QR code.
    @ViewBuilder
    private func composerSheet(_ composer: AppModel.Composer) -> some View {
        switch composer.kind {
        case .link:
            LinkEditorView(prefill: composer.prefill) { _ in
                router.open(.links)
                refreshOverviews()
            }
            .environment(links)
        case .qrCode:
            QRCodeEditorView(prefillURL: composer.prefill) { _ in
                router.open(.qrCodes)
                refreshOverviews()
            }
            .environment(qrCodes)
        case .bioPage:
            CreatePageSheet { page in
                pages.openRequest = page.id
                router.open(.pages)
                refreshOverviews()
            }
            .environment(pages)
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash:
            if let kind = composer.kind.resourceKind {
                ResourceComposerSheet(kind: kind) { _ in
                    router.open(AppDestination(resourceKind: kind))
                    refreshOverviews()
                }
            }
        }
    }
}

/// A link opened from the palette or a deep link, over any tab: its
/// editor with ✕ Close at the leading edge. While the link has unsaved
/// changes the editor shows its own ✕ Cancel (which asks first) in that
/// slot, so Close steps aside rather than doubling it.
private struct PresentedLinkSheet: View {
    let link: Resource
    let close: () -> Void
    /// The editor reports its unsaved changes here (`unsavedChanges`).
    @State private var unsaved = UnsavedChangesTracker()

    var body: some View {
        NavigationStack {
            LinkDetailView(link: link, onDeleted: close)
                .toolbar {
                    if !unsaved.isDirty {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: close) {
                                EditorBarLabel(title: String(localized: "Close"), systemImage: "xmark")
                            }
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                }
        }
        .environment(unsaved)
    }
}

#if DEBUG
private struct MainPreview: View {
    @State private var app = AppModel.preview()

    var body: some View {
        MainView(client: app.client)
            .environment(app)
            .studioViewport()
    }
}

#Preview("Signed in") {
    MainPreview()
}

#endif
