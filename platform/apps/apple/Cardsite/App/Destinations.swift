import SwiftUI
import CardsiteKit

/*
 The navigation registry: one definition, every surface.

 Mirrors the web's apps/web/src/lib/navigation.ts. A destination is
 declared once, with its group, title, glyph, shortcut and iPhone placement,
 and each surface only decides how to draw it:

   · the iPad and Mac sidebar (sections by group)
   · the iPhone tab bar (Home · Links · Library, plus the Search tab) and
     the Library hub, which lists everything else (LibraryGroup)
   · the account sheet (Inbox, Workspace, Preferences, Account & Security)
   · the ⌘K command palette and the Search tab
   · the Go menu and ⌘1…⌘9

 Named `AppDestination` rather than `Destination` because CardsiteKit
 already has a public `Destination` (the URL rules every editor calls as
 `Destination.normalized(_:)`); an app-module `Destination` would shadow it.

 ADDING A DESTINATION is one case below plus one line in `DestinationView`.
 Fill in its group, title and glyph (the switches won't compile until you
 do), and its Library group if it belongs in the hub.

 THE ROOT CONTRACT. Every destination has a stack-free view: content
 with no NavigationStack, which the shell pushes onto Library's stack (or
 Home's, or the account sheet's) on iPhone. Nesting stacks is unsupported
 in SwiftUI. As a sidebar tab on iPad and Mac the shell wraps that view in
 a stack, except for `ownsNavigation` destinations, whose root is a
 self-contained screen with its own NavigationStack or NavigationSplitView
 (Pages' split view; QR Codes' stack around `QRCodesView`). Most feature
 folders ship both shapes (`WorkspaceScreen` wraps `WorkspaceView`); the
 registry uses the stack-free one everywhere but the sidebar.

 ORDER. `allCases` order is sidebar order within a group, and the groups
 run Overview, Content, Organise, Account, as on the web. Content follows
 the web's order (navigation.ts): vCards, payment links, events, splash
 pages, static pages, file links, then uploads and data records.

 IDENTIFIERS. Each Library row carries `nav.<rawValue>`, each account-sheet
 row `account.sheet.<rawValue>`, the avatar `nav.account`, and each
 destination's root content `screen.<rawValue>`, which CardsiteUITests
 finds them by (CardsiteUITests/Harness.swift). Sidebar items and tabs are
 system-drawn and carry no identifier; the tests find them by `title`, so
 keep titles and raw values in step with the harness's `Destination`.
 */
enum AppDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home
    case links
    case pages
    case qrCodes
    case statistics
    case vcards
    case paymentLinks
    case events
    case splashPages
    case staticPages
    case fileLinks
    case uploads
    case data
    case projects
    case domains
    case pixels
    case workspace
    case inbox
    case activity
    case account
    /// Raw value "settings": the UI tests' name for it, and the web's
    /// Settings / Preferences pair is one screen here.
    case preferences = "settings"

    var id: String { rawValue }

    /// Sidebar sections, in order. The web's lead group has no heading.
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case overview, content, organise, account

        var id: String { rawValue }

        /// Nil for the lead group, which sits at the top of the sidebar
        /// without a heading, as on the web.
        var sidebarTitle: String? {
            switch self {
            case .overview: return nil
            case .content: return String(localized: "Content")
            case .organise: return String(localized: "Organize")
            case .account: return String(localized: "Account")
            }
        }

        /// The heading in search and the palette, where every group is titled.
        var title: String {
            sidebarTitle ?? String(localized: "Overview")
        }

        var destinations: [AppDestination] {
            AppDestination.allCases.filter { $0.group == self }
        }
    }

    /// Where a destination sits on iPhone.
    enum PhonePlacement: Sendable {
        /// A tab of its own: Home and Links. The tab bar is exactly these,
        /// Library and the Search tab.
        case tab
        /// Reached through the Library tab: a hub row, or pushed onto
        /// Library's stack by `ShellRouter.open(_:)`.
        case library
        /// A row in the account sheet (the avatar), and pushed onto
        /// Library's stack when opened from search, a deep link or a test.
        case account
    }

    var group: Group {
        switch self {
        case .home, .links, .pages, .qrCodes, .statistics: return .overview
        case .vcards, .paymentLinks, .events, .splashPages, .staticPages, .fileLinks, .uploads, .data:
            return .content
        case .projects, .domains, .pixels: return .organise
        case .workspace, .inbox, .activity, .account, .preferences: return .account
        }
    }

    /// The name in the sidebar, the palette, Library and the Go menu.
    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .links: return String(localized: "Links")
        case .pages: return String(localized: "Pages")
        case .qrCodes: return String(localized: "QR Codes")
        case .statistics: return String(localized: "Statistics")
        case .vcards, .paymentLinks, .events, .splashPages, .staticPages, .fileLinks:
            return resourceKind?.pluralTitle ?? ""
        case .uploads: return String(localized: "Uploads")
        case .data: return String(localized: "Data Records")
        case .projects: return String(localized: "Projects")
        case .domains: return String(localized: "Domains")
        case .pixels: return String(localized: "Pixels")
        case .workspace: return String(localized: "Workspace")
        case .inbox: return String(localized: "Inbox")
        case .activity: return String(localized: "Activity Logs")
        case .account: return String(localized: "Account")
        case .preferences: return String(localized: "Preferences")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .links: return "link"
        case .pages: return "person.crop.square"
        case .qrCodes: return "qrcode"
        case .statistics: return "chart.bar.xaxis"
        case .vcards, .paymentLinks, .events, .splashPages, .staticPages, .fileLinks:
            return resourceKind?.systemImage ?? "square.dashed"
        case .projects: return "folder"
        case .domains: return "globe"
        case .pixels: return "scope"
        case .uploads: return "square.and.arrow.up.on.square"
        case .data: return "tablecells"
        case .workspace: return "person.2"
        case .inbox: return "tray"
        case .activity: return "list.bullet.rectangle"
        case .account: return "person.crop.circle"
        case .preferences: return "slider.horizontal.3"
        }
    }

    var phonePlacement: PhonePlacement {
        switch self {
        case .home, .links: return .tab
        case .pages, .qrCodes, .statistics, .vcards, .paymentLinks, .events, .splashPages, .staticPages,
             .fileLinks, .uploads, .data, .projects, .domains, .pixels, .activity:
            return .library
        case .workspace, .inbox, .account, .preferences:
            return .account
        }
    }

    /// Shown in the tab bar (iPhone, and iPad's tab-bar mode) as well as the
    /// sidebar. Everything else is sidebar-only on iPad and Mac
    /// (`defaultVisibility(.hidden, for: .tabBar)`).
    var isInTabBar: Bool { phonePlacement == .tab }

    /// ⌘ plus this key, from the Go menu on Mac and the shortcut HUD on iPad.
    /// ⌘1…⌘9 belong to the main destinations; ⌘N, ⇧⌘N and ⌘K are taken.
    var shortcut: KeyEquivalent? {
        switch self {
        case .home: return "1"
        case .links: return "2"
        case .pages: return "3"
        case .qrCodes: return "4"
        case .statistics: return "5"
        case .inbox: return "6"
        case .workspace: return "7"
        case .vcards, .paymentLinks, .events, .splashPages, .staticPages, .fileLinks,
             .uploads, .data, .projects, .domains, .pixels, .activity, .account, .preferences:
            return nil
        }
    }

    /// Extra words the palette and search match, beyond the title.
    var keywords: [String] {
        switch self {
        case .home: return [String(localized: "dashboard"), String(localized: "overview")]
        case .links: return [String(localized: "short links"), String(localized: "addresses")]
        case .pages: return [String(localized: "bio pages"), String(localized: "link in bio")]
        case .qrCodes: return [String(localized: "codes"), String(localized: "scan")]
        case .statistics: return [String(localized: "analytics"), String(localized: "traffic"),
                                  String(localized: "clicks")]
        case .vcards: return [String(localized: "contact cards"), String(localized: "business cards")]
        case .paymentLinks: return [String(localized: "checkout"), String(localized: "payments")]
        case .events: return [String(localized: "calendar"), String(localized: "invitations")]
        case .splashPages: return [String(localized: "interstitial"), String(localized: "redirect page")]
        case .staticPages: return [String(localized: "HTML"), String(localized: "website"), String(localized: "hosting")]
        case .fileLinks: return [String(localized: "files"), String(localized: "downloads"), String(localized: "documents")]
        case .projects: return [String(localized: "folders"), String(localized: "organize"), String(localized: "organise")]
        case .domains: return [String(localized: "custom domains"), String(localized: "DNS"), String(localized: "branded")]
        case .pixels: return [String(localized: "tracking"), String(localized: "retargeting"), String(localized: "analytics")]
        case .uploads: return [String(localized: "files"), String(localized: "images"), String(localized: "media")]
        case .data: return [String(localized: "form submissions"), String(localized: "records")]
        case .workspace: return [String(localized: "team"), String(localized: "members"), String(localized: "invite")]
        case .inbox: return [String(localized: "notifications"), String(localized: "announcements")]
        case .activity: return [String(localized: "logs"), String(localized: "sign-ins"), String(localized: "security")]
        case .account: return [String(localized: "profile"), String(localized: "security"),
                               String(localized: "password"), String(localized: "sign out")]
        case .preferences: return [String(localized: "settings"), String(localized: "defaults"),
                                   String(localized: "options")]
        }
    }

    /// The resource type a Content destination lists, nil for the rest.
    var resourceKind: ResourceKind? {
        switch self {
        case .vcards: return .vcard
        case .paymentLinks: return .paymentLink
        case .events: return .event
        case .splashPages: return .splash
        case .staticPages: return .staticPage
        case .fileLinks: return .file
        default: return nil
        }
    }

    /// The list a resource type lives in.
    init(resourceKind: ResourceKind) {
        switch resourceKind {
        case .vcard: self = .vcards
        case .paymentLink: self = .paymentLinks
        case .event: self = .events
        case .splash: self = .splashPages
        case .staticPage: self = .staticPages
        case .file: self = .fileLinks
        }
    }

    /// Destinations whose sidebar root brings its own NavigationStack or
    /// NavigationSplitView (see the root contract). Their pushed form is
    /// stack-free like everyone else's.
    var ownsNavigation: Bool {
        switch self {
        case .home, .links, .pages, .qrCodes: return true
        default: return false
        }
    }

    /// True when iPhone shows this destination pushed onto Library's stack
    /// rather than as a tab: everything but Home and Links. Every one of
    /// them has a stack-free view (Pages: `PagesStackView`, QR Codes:
    /// `QRCodesView`), so the router never selects a tab that the iPhone
    /// tab bar doesn't show.
    var pushesOntoLibrary: Bool { phonePlacement != .tab }

    /// `nav.<rawValue>`: the Library hub row (the avatar for `.account`).
    var navIdentifier: String { "nav.\(rawValue)" }
    /// `account.sheet.<rawValue>`: the account sheet's row.
    var accountSheetIdentifier: String { "account.sheet.\(rawValue)" }
    /// `screen.<rawValue>`: the destination's root view.
    var screenIdentifier: String { "screen.\(rawValue)" }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedStandardContains(query) }
    }
}

/// The view for each destination: the single switch the registry's root
/// contract describes. Stack-free unless `isSidebarRoot`, which only
/// ``DestinationRoot`` passes.
struct DestinationView: View {
    @Environment(AppModel.self) private var app
    @Environment(InboxModel.self) private var inbox
    let destination: AppDestination
    /// True for a sidebar tab's root, where `ownsNavigation` destinations
    /// bring their own stack or split view.
    var isSidebarRoot = false

    var body: some View {
        if destination.ownsNavigation {
            // A tab root is a NavigationStack or NavigationSplitView, and an
            // identifier on that container doesn't surface to XCUITest. Those
            // screens (and their stack-free forms) stamp `screen.<rawValue>`
            // on their own primary content.
            root
        } else {
            root
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(destination.screenIdentifier)
        }
    }

    @ViewBuilder
    private var root: some View {
        switch destination {
        case .home: HomeScreen()
        case .links: LinksScreen()
        case .pages:
            if isSidebarRoot { PagesScreen() } else { PagesStackView() }
        case .qrCodes:
            if isSidebarRoot { QRCodesScreen() } else { QRCodesView() }
        case .statistics: StatisticsScreen(linkID: nil)
        case .vcards: ResourceListScreen(kind: .vcard)
        case .paymentLinks: ResourceListScreen(kind: .paymentLink)
        case .events: ResourceListScreen(kind: .event)
        case .splashPages: ResourceListScreen(kind: .splash)
        case .staticPages: ResourceListScreen(kind: .staticPage)
        case .fileLinks: ResourceListScreen(kind: .file)
        case .uploads: UploadsView(client: app.client, onError: onError)
        case .data: DataRecordsView(client: app.client, onError: onError)
        case .projects: ProjectsView(client: app.client, onError: onError)
        case .domains: DomainsView(client: app.client, onError: onError)
        case .pixels: PixelsView(client: app.client, onError: onError)
        case .workspace: WorkspaceView(client: app.client, onError: onError)
        case .inbox: InboxView(model: inbox)
        case .activity: ActivityLogsView(client: app.client, onError: onError)
        case .account: AccountView(client: app.client, onError: onError)
        case .preferences: PreferencesView(client: app.client, onError: onError)
        }
    }

    private var onError: @MainActor (any Error) -> Void {
        { [app] error in app.handle(error) }
    }
}

/// A destination as a sidebar tab: wrapped in a stack unless it brings its own.
struct DestinationRoot: View {
    let destination: AppDestination

    var body: some View {
        if destination.ownsNavigation {
            DestinationView(destination: destination, isSidebarRoot: true)
        } else {
            NavigationStack {
                DestinationView(destination: destination)
            }
        }
    }
}

// MARK: - Create actions

/// Everything the app can create, for the File menu, the `+` menus, the
/// palette, search and Home's quick-create tiles. Add a case when a new
/// editor lands, with the composer that opens it.
enum CreateAction: String, CaseIterable, Hashable, Identifiable, Sendable {
    case shortLink
    case qrCode
    case bioPage
    case vcard
    case event
    case paymentLink
    case file
    case staticPage
    case splash

    var id: String { rawValue }

    /// The most-used types, for Home's quick-create tiles. The New menus,
    /// the File menu and the palette list every case.
    static let featured: [CreateAction] = [.shortLink, .qrCode, .bioPage, .vcard, .file]

    /// The `+` menu's sections: what you publish, what people save or pay,
    /// and what you host.
    static let menuGroups: [[CreateAction]] = [
        [.shortLink, .qrCode, .bioPage],
        [.vcard, .event, .paymentLink],
        [.file, .staticPage, .splash],
    ]

    /// The resource type this action creates, for the six resource kinds.
    var resourceKind: ResourceKind? {
        switch self {
        case .shortLink, .qrCode, .bioPage: return nil
        case .vcard: return .vcard
        case .event: return .event
        case .paymentLink: return .paymentLink
        case .file: return .file
        case .staticPage: return .staticPage
        case .splash: return .splash
        }
    }

    /// The menu command: "New Short Link".
    var title: String {
        switch self {
        case .shortLink: return String(localized: "New Short Link")
        case .qrCode: return String(localized: "New QR Code")
        case .bioPage: return String(localized: "New Bio Page")
        case .vcard: return String(localized: "New vCard")
        case .event: return String(localized: "New Event")
        case .paymentLink: return String(localized: "New Payment Link")
        case .file: return String(localized: "New File Link")
        case .staticPage: return String(localized: "New Static Page")
        case .splash: return String(localized: "New Splash Page")
        }
    }

    /// The product's own name, as the web registry spells it.
    var kindTitle: String {
        switch self {
        case .shortLink: return String(localized: "Short link")
        case .qrCode: return String(localized: "QR code")
        case .bioPage: return String(localized: "Bio page")
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash:
            return resourceKind?.title ?? ""
        }
    }

    /// The quick-create tile's line, from the web dashboard.
    var blurb: String {
        switch self {
        case .shortLink: return String(localized: "Paste a long URL, get a short one")
        case .qrCode: return String(localized: "Scannable, fully styled")
        case .bioPage: return String(localized: "A page in minutes")
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash:
            return resourceKind?.blurb ?? ""
        }
    }

    var systemImage: String {
        switch self {
        case .shortLink: return "link.badge.plus"
        case .qrCode: return "qrcode"
        case .bioPage: return "person.crop.square"
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash:
            return resourceKind?.systemImage ?? "plus"
        }
    }

    var composer: AppModel.Composer {
        switch self {
        case .shortLink: return .link
        case .qrCode: return .qrCode
        case .bioPage: return .bioPage
        case .vcard: return AppModel.Composer(kind: .vcard)
        case .event: return AppModel.Composer(kind: .event)
        case .paymentLink: return AppModel.Composer(kind: .paymentLink)
        case .file: return AppModel.Composer(kind: .file)
        case .staticPage: return AppModel.Composer(kind: .staticPage)
        case .splash: return AppModel.Composer(kind: .splash)
        }
    }

    /// ⌘N, ⇧⌘N and ⌥⌘N; the resource types have none.
    var shortcut: KeyboardShortcut? {
        switch self {
        case .shortLink: return KeyboardShortcut("n", modifiers: .command)
        case .qrCode: return KeyboardShortcut("n", modifiers: [.command, .shift])
        case .bioPage: return KeyboardShortcut("n", modifiers: [.command, .option])
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash: return nil
        }
    }

    /// The shortcut as the palette prints it.
    var shortcutLabel: String? {
        switch self {
        case .shortLink: return "⌘N"
        case .qrCode: return "⇧⌘N"
        case .bioPage: return "⌥⌘N"
        case .vcard, .event, .paymentLink, .file, .staticPage, .splash: return nil
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [title, kindTitle, blurb].contains { $0.localizedStandardContains(query) }
    }
}

// MARK: - Shell router

/// The tab bar and sidebar selection.
enum MainTab: Hashable, Sendable {
    case destination(AppDestination)
    /// The Library hub: a tab on iPhone (and in iPad's tab-bar mode), not
    /// in the sidebar, which lists every destination itself.
    case library
    /// The search tab (`Tab(role: .search)`); the sidebar's search field
    /// on iPad and Mac.
    case search

    init(storageKey: String) {
        if let destination = AppDestination(rawValue: storageKey) {
            self = .destination(destination)
        } else if storageKey == Self.searchKey {
            self = .search
        } else {
            #if os(macOS)
            // The Mac has no Library tab: its sidebar lists every
            // destination.
            self = .destination(.home)
            #else
            self = .library
            #endif
        }
    }

    static let libraryKey = "library"
    static let searchKey = "search"
}

/// Navigation state for one window: the selected tab, Library's stack, the
/// account sheet, the palette and the link opened from it. Lives in
/// `MainView`, reaches the screens through the environment and the menu bar
/// through `focusedSceneValue`, so every surface navigates the same way.
@MainActor
@Observable
final class ShellRouter {
    var tab: MainTab = .destination(.home)
    /// Library's stack on iPhone: destinations (`AppDestination`) and the
    /// resources opened from the Recently edited shelf (`Resource`).
    var libraryPath = NavigationPath()
    /// The destination most recently pushed onto `libraryPath`, so the tab
    /// can be restored and moved to the sidebar when the width changes.
    private(set) var libraryTop: AppDestination?
    var isPalettePresented = false
    /// The account sheet, from the avatar on Home and Library.
    var isAccountPresented = false
    /// A link opened from the palette, shown in a sheet over any tab.
    var presentedLink: Resource?
    /// True on iPhone and in compact-width iPad windows, where the shell is
    /// a tab bar (Home · Links · Library · Search) rather than a sidebar.
    private(set) var isCompact = false

    /// Goes to a destination the way the current layout shows it: its
    /// sidebar item on iPad and Mac; on iPhone its tab, or pushed onto
    /// Library's stack. Deep links, the palette, search, the Go menu and
    /// UI tests' `-CardsiteOpen` all come through here. On iPhone it never
    /// selects a tab the tab bar doesn't show.
    func open(_ destination: AppDestination) {
        isPalettePresented = false
        presentedLink = nil
        isAccountPresented = false
        if isCompact && destination.pushesOntoLibrary {
            libraryPath = NavigationPath([destination])
            libraryTop = destination
            tab = .library
        } else {
            tab = .destination(destination)
        }
    }

    /// A Library hub row: pushes the destination's stack-free view onto
    /// Library's stack, in any layout that shows the hub.
    func showFromLibrary(_ destination: AppDestination) {
        guard destination.pushesOntoLibrary else {
            open(destination)
            return
        }
        libraryPath.append(destination)
        libraryTop = destination
    }

    func togglePalette() {
        isPalettePresented.toggle()
    }

    /// Moves the selection between the two structures when the width
    /// class changes, the way Apple's sidebar-adaptable sample does: a
    /// sidebar-only destination becomes Library's stack on iPhone, and its
    /// own sidebar item again on iPad and Mac.
    func adapt(isCompact compact: Bool) {
        isCompact = compact
        switch tab {
        case .destination(let destination)
            where compact && destination.pushesOntoLibrary:
            libraryPath = NavigationPath([destination])
            libraryTop = destination
            tab = .library
        case .library where !compact && !libraryPath.isEmpty:
            tab = .destination(libraryTop ?? .home)
            libraryPath = NavigationPath()
            libraryTop = nil
        default:
            break
        }
    }

    /// What `@SceneStorage` keeps: the destination on screen, even when it
    /// is inside Library.
    var storageKey: String {
        switch tab {
        case .destination(let destination): return destination.rawValue
        case .search: return MainTab.searchKey
        case .library:
            guard !libraryPath.isEmpty, let libraryTop else { return MainTab.libraryKey }
            return libraryTop.rawValue
        }
    }
}

struct ShellRouterKey: FocusedValueKey {
    typealias Value = ShellRouter
}

extension FocusedValues {
    /// The focused window's router, for menu commands.
    var shellRouter: ShellRouter? {
        get { self[ShellRouterKey.self] }
        set { self[ShellRouterKey.self] = newValue }
    }
}
