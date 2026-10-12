import SwiftUI
import CardsiteKit

/*
 The navigation registry: one definition, every surface.

 Mirrors the web's apps/web/src/lib/navigation.ts. A destination is
 declared once, with its group, title, glyph, shortcut and iPhone placement,
 and each surface only decides how to draw it:

   · the iPad and Mac sidebar (sections by group)
   · the iPhone tab bar (Home · Links · Pages · QR) and More (the rest, grouped)
   · the ⌘K command palette and iPhone search on Home
   · the Go menu and ⌘1…⌘9

 Named `AppDestination` rather than `Destination` because CardsiteKit
 already has a public `Destination` (the URL rules every editor calls as
 `Destination.normalized(_:)`); an app-module `Destination` would shadow it.

 ADDING A DESTINATION is one case below plus one line in `DestinationView`.
 Fill in its group, title and glyph (the switches won't compile until you
 do), and `iPhoneTab` if it earns a tab.

 THE ROOT CONTRACT. A `.tab` destination's view is a self-contained
 screen that owns its navigation (a NavigationStack or NavigationSplitView).
 A `.more` destination's view must NOT contain a NavigationStack: the shell
 wraps it in one when it is a sidebar item, and pushes it onto More's stack
 on iPhone. Nesting stacks is unsupported in SwiftUI. Most feature folders
 already ship both shapes (`WorkspaceScreen` wraps `WorkspaceView`); register
 the inner one.

 Planned, once their screens exist (one case each):
   content   · vCards, events, paymentLinks, files, staticPages, splashPages
   organise  · projects, domains, pixels

 IDENTIFIERS. Each sidebar item, tab and More row carries `nav.<rawValue>`
 and each destination's root `screen.<rawValue>`, which CardsiteUITests
 finds them by (CardsiteUITests/Harness.swift). Keep raw values stable.
 */
enum AppDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home
    case links
    case pages
    case qrCodes
    case statistics
    case uploads
    case data
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
            case .organise: return String(localized: "Organise")
            case .account: return String(localized: "Account")
            }
        }

        /// The heading in More and in search, where every group is titled.
        var title: String {
            sidebarTitle ?? String(localized: "Overview")
        }

        var destinations: [AppDestination] {
            AppDestination.allCases.filter { $0.group == self }
        }
    }

    /// Where a destination sits on iPhone.
    enum IPhonePlacement: Sendable {
        /// A tab of its own. Keep these to four, plus More.
        case tab
        /// A row in More.
        case more
    }

    var group: Group {
        switch self {
        case .home, .links, .pages, .qrCodes, .statistics: return .overview
        case .uploads, .data: return .content
        case .workspace, .inbox, .activity, .account, .preferences: return .account
        }
    }

    /// The name in the sidebar, the palette, More and the Go menu.
    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .links: return String(localized: "Links")
        case .pages: return String(localized: "Pages")
        case .qrCodes: return String(localized: "QR Codes")
        case .statistics: return String(localized: "Statistics")
        case .uploads: return String(localized: "Uploads")
        case .data: return String(localized: "Data Records")
        case .workspace: return String(localized: "Workspace")
        case .inbox: return String(localized: "Inbox")
        case .activity: return String(localized: "Activity Logs")
        case .account: return String(localized: "Account")
        case .preferences: return String(localized: "Preferences")
        }
    }

    /// The tab bar's shorter name, where the full one is too wide.
    var tabTitle: String {
        switch self {
        case .qrCodes: return String(localized: "QR")
        default: return title
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .links: return "link"
        case .pages: return "person.crop.square"
        case .qrCodes: return "qrcode"
        case .statistics: return "chart.bar.xaxis"
        case .uploads: return "square.and.arrow.up.on.square"
        case .data: return "tablecells"
        case .workspace: return "person.2"
        case .inbox: return "tray"
        case .activity: return "list.bullet.rectangle"
        case .account: return "person.crop.circle"
        case .preferences: return "slider.horizontal.3"
        }
    }

    var iPhoneTab: IPhonePlacement {
        switch self {
        case .home, .links, .pages, .qrCodes: return .tab
        case .statistics, .uploads, .data, .workspace, .inbox, .activity, .account, .preferences: return .more
        }
    }

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
        case .uploads, .data, .activity, .account, .preferences: return nil
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

    /// The tab bar's own roots own their navigation; everything else is
    /// stack-free content the shell wraps or pushes (see the root contract).
    var ownsNavigation: Bool { iPhoneTab == .tab }

    /// `nav.<rawValue>`: the sidebar item, tab or More row.
    var navIdentifier: String { "nav.\(rawValue)" }
    /// `screen.<rawValue>`: the destination's root view.
    var screenIdentifier: String { "screen.\(rawValue)" }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedStandardContains(query) }
    }
}

/// The view for each destination: the single switch the registry's root
/// contract describes.
struct DestinationView: View {
    @Environment(AppModel.self) private var app
    @Environment(InboxModel.self) private var inbox
    let destination: AppDestination

    var body: some View {
        root
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(destination.screenIdentifier)
    }

    @ViewBuilder
    private var root: some View {
        switch destination {
        case .home: HomeScreen()
        case .links: LinksScreen()
        case .pages: PagesScreen()
        case .qrCodes: QRCodesScreen()
        case .statistics: StatisticsScreen(linkID: nil)
        case .uploads: UploadsView(client: app.client, onError: onError)
        case .data: DataRecordsView(client: app.client, onError: onError)
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
            DestinationView(destination: destination)
        } else {
            NavigationStack {
                DestinationView(destination: destination)
            }
        }
    }
}

// MARK: - Create actions

/// Everything the app can create, for the File menu, the New menus, the
/// palette, search and Home's quick-create tiles. Add a case when a new
/// editor lands (bio page, vCard, event, file link…), with the composer
/// that opens it.
enum CreateAction: String, CaseIterable, Hashable, Identifiable, Sendable {
    case shortLink
    case qrCode
    case bioPage

    var id: String { rawValue }

    /// The menu command: "New Short Link".
    var title: String {
        switch self {
        case .shortLink: return String(localized: "New Short Link")
        case .qrCode: return String(localized: "New QR Code")
        case .bioPage: return String(localized: "New Bio Page")
        }
    }

    /// The product's own name, as the web registry spells it.
    var kindTitle: String {
        switch self {
        case .shortLink: return String(localized: "Short link")
        case .qrCode: return String(localized: "QR code")
        case .bioPage: return String(localized: "Bio page")
        }
    }

    /// The quick-create tile's line, from the web dashboard.
    var blurb: String {
        switch self {
        case .shortLink: return String(localized: "Paste a long URL, get a short one")
        case .qrCode: return String(localized: "Scannable, fully styled")
        case .bioPage: return String(localized: "A page in minutes")
        }
    }

    var systemImage: String {
        switch self {
        case .shortLink: return "link.badge.plus"
        case .qrCode: return "qrcode"
        case .bioPage: return "person.crop.square"
        }
    }

    var composer: AppModel.Composer {
        switch self {
        case .shortLink: return .link
        case .qrCode: return .qrCode
        case .bioPage: return .bioPage
        }
    }

    var shortcut: KeyboardShortcut {
        switch self {
        case .shortLink: return KeyboardShortcut("n", modifiers: .command)
        case .qrCode: return KeyboardShortcut("n", modifiers: [.command, .shift])
        case .bioPage: return KeyboardShortcut("n", modifiers: [.command, .option])
        }
    }

    /// The shortcut as the palette prints it.
    var shortcutLabel: String {
        switch self {
        case .shortLink: return "⌘N"
        case .qrCode: return "⇧⌘N"
        case .bioPage: return "⌥⌘N"
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
    /// iPhone only: everything that isn't a tab.
    case more

    init(storageKey: String) {
        if let destination = AppDestination(rawValue: storageKey) {
            self = .destination(destination)
        } else {
            self = .more
        }
    }
}

/// Navigation state for one window: the selected tab, More's stack, the
/// palette and the link opened from it. Lives in `MainView`, reaches the
/// screens through the environment and the menu bar through
/// `focusedSceneValue`, so every surface navigates the same way.
@MainActor
@Observable
final class ShellRouter {
    var tab: MainTab = .destination(.home)
    var morePath: [AppDestination] = []
    var isPalettePresented = false
    /// A link opened from the palette, shown in a sheet over any tab.
    var presentedLink: Resource?
    /// True on iPhone and in compact-width iPad windows, where the shell is
    /// a tab bar with More rather than a sidebar.
    private(set) var isCompact = false

    /// Goes to a destination the way the current layout shows it.
    func open(_ destination: AppDestination) {
        isPalettePresented = false
        presentedLink = nil
        if isCompact && destination.iPhoneTab == .more {
            morePath = [destination]
            tab = .more
        } else {
            tab = .destination(destination)
        }
    }

    func togglePalette() {
        isPalettePresented.toggle()
    }

    /// Moves the selection between the two structures when the width
    /// class changes, the way Apple's sidebar-adaptable sample does: a
    /// More destination becomes More's stack on iPhone, and its own
    /// sidebar item again on iPad and Mac.
    func adapt(isCompact compact: Bool) {
        isCompact = compact
        switch tab {
        case .destination(let destination) where compact && destination.iPhoneTab == .more:
            morePath = [destination]
            tab = .more
        case .more where !compact:
            tab = .destination(morePath.last ?? .home)
            morePath = []
        default:
            break
        }
    }

    /// What `@SceneStorage` keeps: the destination on screen, even when it
    /// is inside More.
    var storageKey: String {
        switch tab {
        case .destination(let destination): return destination.rawValue
        case .more: return morePath.last?.rawValue ?? "more"
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
