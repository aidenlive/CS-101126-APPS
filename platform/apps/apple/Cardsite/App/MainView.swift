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
/// · iPad and Mac: a sidebar. Overview destinations sit at the top with no
///   heading, as on the web, and the other groups are `TabSection`s. The
///   workspace switcher heads the sidebar.
/// · iPhone (and compact-width iPad windows): a tab bar of Home, Links,
///   Pages, QR and More. More is a native grouped list of everything else,
///   with the workspace switcher at the top.
///
/// A `NavigationSplitView` shell was the alternative. It was rejected
/// because Links and QR Codes are themselves split views (list and detail),
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
    @State private var search: QuickSearchModel
    /// One for the session, so the badge and the Inbox list agree.
    @State private var inbox: InboxModel

    init(client: APIClient) {
        _links = State(initialValue: LinksModel(client: client))
        _qrCodes = State(initialValue: QRCodesModel(client: client))
        _pages = State(initialValue: PagesModel(client: client))
        _home = State(initialValue: HomeModel(client: client))
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

    /// Sidebar sections after the lead group, skipping any with nothing in
    /// them yet.
    private var sectionGroups: [AppDestination.Group] {
        AppDestination.Group.allCases.filter { $0 != .overview && !$0.destinations.isEmpty }
    }

    var body: some View {
        @Bindable var nav = router
        @Bindable var app = model

        TabView(selection: $nav.tab) {
            ForEach(AppDestination.Group.overview.destinations) { destination in
                Tab(isCompact ? destination.tabTitle : destination.title,
                    systemImage: destination.systemImage,
                    value: MainTab.destination(destination)) {
                    DestinationRoot(destination: destination)
                }
                .badge(badgeCount(for: destination))
                .accessibilityIdentifier(destination.navIdentifier)
                .hidden(isCompact && destination.iPhoneTab == .more)
            }

            Tab(String(localized: "More"), systemImage: "ellipsis.circle", value: MainTab.more) {
                MoreScreen()
            }
            .badge(isCompact ? inbox.unreadCount : 0)
            .accessibilityIdentifier("nav.more")
            .hidden(!isCompact)

            ForEach(sectionGroups) { group in
                TabSection(group.title) {
                    ForEach(group.destinations) { destination in
                        Tab(destination.title,
                            systemImage: destination.systemImage,
                            value: MainTab.destination(destination)) {
                            DestinationRoot(destination: destination)
                        }
                        .badge(badgeCount(for: destination))
                        .accessibilityIdentifier(destination.navIdentifier)
                    }
                }
                .hidden(isCompact)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            WorkspaceSwitcher()
                .padding(.bottom, StudioSpace.s2)
        }
        .overlay {
            if router.isPalettePresented {
                CommandPalette()
                    .transition(reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? StudioAnimation.base : StudioAnimation.spring, value: router.isPalettePresented)
        // A view presents one sheet at a time: while a link from the
        // palette is up, its own sheet presents the composer instead (its
        // "Create QR code"), so this one stands down.
        .sheet(item: Binding(get: { [router, model] in router.presentedLink == nil ? model.composer : nil },
                             set: { [model] in model.composer = $0 })) { composer in
            composerSheet(composer)
        }
        .sheet(item: $nav.presentedLink) { link in
            NavigationStack {
                LinkDetailView(link: link, onDeleted: { router.presentedLink = nil })
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { router.presentedLink = nil }
                        }
                    }
            }
            .sheet(item: $app.composer) { composer in
                composerSheet(composer)
            }
            .environment(links)
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            #endif
        }
        .environment(router)
        .environment(links)
        .environment(qrCodes)
        .environment(pages)
        .environment(home)
        .environment(search)
        .environment(inbox)
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
            search.onError = model.handle
            inbox.onError = model.handle
            router.tab = MainTab(storageKey: storedTab)
            router.adapt(isCompact: isCompact)
        }
        .onChange(of: isCompact) { _, compact in
            router.adapt(isCompact: compact)
        }
        .onChange(of: router.storageKey) { _, key in
            storedTab = key
        }
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
                Task { [home] in await home.refresh() }
            }
            .environment(links)
        case .qrCode:
            QRCodeEditorView(prefillURL: composer.prefill) { _ in
                router.open(.qrCodes)
                Task { [home] in await home.refresh() }
            }
            .environment(qrCodes)
        case .bioPage:
            CreatePageSheet { page in
                pages.openRequest = page.id
                router.open(.pages)
                Task { [home] in await home.refresh() }
            }
            .environment(pages)
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash:
            if let kind = composer.kind.resourceKind {
                ResourceComposerSheet(kind: kind) { _ in
                    router.open(AppDestination(resourceKind: kind))
                    Task { [home] in await home.refresh() }
                }
            }
        }
    }
}

/// iPhone's More tab: every destination without a tab of its own, grouped
/// as in the sidebar, under the workspace switcher.
struct MoreScreen: View {
    @Environment(ShellRouter.self) private var router
    @Environment(InboxModel.self) private var inbox

    private var groups: [AppDestination.Group] {
        AppDestination.Group.allCases.filter { group in
            group.destinations.contains { $0.iPhoneTab == .more }
        }
    }

    var body: some View {
        @Bindable var nav = router
        NavigationStack(path: $nav.morePath) {
            List {
                Section {
                    WorkspacePickerRow()
                } header: {
                    Text("Workspace")
                } footer: {
                    Text("Links, pages and codes belong to a workspace. Switch to see another one's.")
                }

                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.destinations.filter { $0.iPhoneTab == .more }) { destination in
                            NavigationLink(value: destination) {
                                Label(destination.title, systemImage: destination.systemImage)
                                    .studioText(.ui)
                            }
                            .badge(destination == .inbox ? inbox.unreadCount : 0)
                            .accessibilityIdentifier(destination.navIdentifier)
                        }
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: AppDestination.self) { destination in
                DestinationView(destination: destination)
            }
        }
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

#Preview("More") {
    let app = AppModel.preview()
    let router = ShellRouter()
    router.adapt(isCompact: true)
    return MoreScreen()
        .environment(app)
        .environment(router)
        .environment(InboxModel(client: app.client))
}
#endif
