import SwiftUI
import StudioKit

/*
 One page and row treatment for every List and Form in the app.

     List { … }.studioList()                 // a list destination
     Form { … }.studioForm()                 // Account, Workspace, editors
     Section { … }.studioRowBackground()     // Studio rows inside either

 Both put the page on `studioBg`, hide the system grouped background, and
 cap the rows at a ``CardsiteMeasure`` through the scroll content's margins,
 so on a wide iPad or Mac window the rows sit in a centred column while the
 scroll indicator stays at the window edge. On iPhone the system margins
 are kept.

 Full-width list destinations (resource lists, Organize, Library, Inbox,
 Workspace) open with ``ListPageHead`` as their first section and an inline
 navigation title; split-view list columns and Forms keep the native large
 title (PARITY-PLAN §6).
 */

extension View {
    /// The Studio look for a native grouped form: opaque Studio background,
    /// Studio body type and tint, rows capped at `measure` on wide windows.
    /// Give each section ``studioRowBackground()`` for Studio row surfaces.
    /// The Mac Settings window keeps the system look.
    func studioForm(measure: CardsiteMeasure = .reading) -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.studioBg)
            .studioText(.ui)
            .tint(Color.studioAccentLine)
            .modifier(MeasuredScrollContent(measure: measure))
    }

    /// The twin of ``studioForm(measure:)`` for a `List`: Studio page
    /// background instead of the system grouped grey, rows capped at
    /// `measure` on wide windows. Give rows or sections
    /// ``studioRowBackground()``.
    func studioList(measure: CardsiteMeasure = .reading) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.studioBg)
            .tint(Color.studioAccentLine)
            .modifier(MeasuredScrollContent(measure: measure))
    }

    /// The Studio row surface for a row or section inside ``studioList(measure:)``
    /// or ``studioForm(measure:)``. On a `Group` of sections it reaches every row.
    func studioRowBackground() -> some View {
        listRowBackground(Color.studioSurface)
    }

    /// The row surface for a selectable row (a split view's list column):
    /// a custom row background replaces the system's selection highlight,
    /// so the selected row draws the accent-soft fill instead.
    func studioRowBackground(isSelected: Bool) -> some View {
        listRowBackground(isSelected ? Color.studioAccentSoft : Color.studioSurface)
    }

    /// A row that draws its own surface (a banner, a page head): no cell
    /// fill and no separator.
    func studioClearRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Centres a scroll view's content in a column no wider than `measure`
/// once the window is wide enough; below that the system margins apply.
private struct MeasuredScrollContent: ViewModifier {
    let measure: CardsiteMeasure
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }

    /// nil keeps the system's margins (iPhone, narrow windows).
    private var inset: CGFloat? {
        let gutter = StudioSpace.s5
        guard width > measure.width + gutter * 2 else { return nil }
        return max(gutter, (width - measure.width) / 2)
    }
}

// MARK: - Page head in a list

/// The page head of a full-width list destination, as its first section:
/// kicker, display title and the web's one-line description, on the page
/// background. Pair it with ``inlineNavigationTitle()`` so the title
/// doesn't appear twice.
///
///     List {
///         ListPageHead(kicker: String(localized: "Organize"),
///                      title: String(localized: "Projects"),
///                      description: String(localized: "Group resources into color-coded projects."))
///         Section { … }
///     }
struct ListPageHead<Actions: View>: View {
    let kicker: String
    let title: String
    var accent: String = ""
    var description: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        Section {
            StudioPageHead(kicker: kicker, title: title, accent: accent, description: description) {
                actions()
            }
            .accessibilityElement(children: .contain)
            .listRowInsets(EdgeInsets(top: StudioSpace.s6, leading: 0, bottom: StudioSpace.s2, trailing: 0))
            .studioClearRow()
        }
    }
}

extension ListPageHead where Actions == EmptyView {
    init(kicker: String, title: String, accent: String = "", description: String? = nil) {
        self.init(kicker: kicker, title: title, accent: accent, description: description) { EmptyView() }
    }
}

extension View {
    /// The navigation title stays (back button, window title, VoiceOver)
    /// but draws inline on iOS, under a page that carries its own head.
    func inlineNavigationTitle() -> some View {
        #if os(iOS) || os(visionOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}

// MARK: - Sheets

/// The two sheet sizes. `.page` for content that needs the room
/// (Statistics, the QR builder, resource editors); `.form` for everything
/// else.
enum CardsiteSheetSize: Sendable {
    case form
    case page
}

extension View {
    /// Sizes a sheet's root view: `presentationSizing` on iPad (iOS 18),
    /// minimum and ideal frames on the Mac. Apply it to the sheet's
    /// outermost view (usually its `NavigationStack`).
    @ViewBuilder
    func cardsiteSheet(_ size: CardsiteSheetSize) -> some View {
        #if os(macOS)
        frame(
            minWidth: size == .page ? 720 : 480,
            idealWidth: size == .page ? 900 : CardsiteMeasure.sheet.width,
            minHeight: size == .page ? 600 : 420
        )
        #else
        // Two branches: `.page` and `.form` are different sizing types.
        switch size {
        case .page: presentationSizing(.page)
        case .form: presentationSizing(.form)
        }
        #endif
    }
}

#Preview("List page head") {
    NavigationStack {
        List {
            ListPageHead(kicker: "Organize", title: "Projects",
                         description: "Group resources into color-coded projects.")
            Section {
                Text("Clients")
                Text("Launch week")
            }
            .studioRowBackground()
        }
        .studioList()
        .navigationTitle("Projects")
        .inlineNavigationTitle()
    }
}
