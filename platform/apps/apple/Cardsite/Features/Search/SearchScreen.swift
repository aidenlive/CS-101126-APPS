import SwiftUI
import StudioKit
import CardsiteKit

/// The Search tab (`Tab(role: .search)`): the system splits it off as the
/// trailing circle of the iPhone tab bar, and makes it the sidebar's search
/// field on iPad and Mac. `MainView` puts `.searchable` on the `TabView`,
/// bound to the shared ``QuickSearchModel``, and the tab view hands the
/// field to this tab.
///
/// With no query it suggests where to go, what to make and what to type;
/// with one it shows ``QuickSearchResults`` (destinations, create actions
/// and the workspace's links). Links push their detail in this tab's stack.
struct SearchScreen: View {
    @Environment(QuickSearchModel.self) private var search

    var body: some View {
        NavigationStack {
            Group {
                if search.trimmedQuery.isEmpty {
                    SearchSuggestions()
                } else {
                    QuickSearchResults()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.search")
            .navigationTitle("Search")
            .navigationDestination(for: Resource.self) { link in
                LinkDetailView(link: link)
            }
        }
    }
}

/// Search before a query: a Studio head, then the places people go most,
/// the things they make most, and a few words to try.
struct SearchSuggestions: View {
    @Environment(AppModel.self) private var app
    @Environment(QuickSearchModel.self) private var search
    @Environment(ShellRouter.self) private var router

    /// The destinations worth a shortcut from search: the ones without a
    /// tab of their own that people open most.
    static let destinations: [AppDestination] = [.pages, .qrCodes, .statistics, .inbox, .uploads]

    /// Words that show what search covers, each one a working query.
    static let tries: [String] = [
        String(localized: "QR"),
        String(localized: "vCard"),
        String(localized: "Domains"),
        String(localized: "Analytics"),
        String(localized: "Payment"),
    ]

    var body: some View {
        List {
            ListPageHead(kicker: String(localized: "Pages · Actions · Links"),
                         title: String(localized: "Find "),
                         accent: String(localized: "anything."),
                         description: String(localized: "Pages, actions and links in this workspace. Type a word, or start from here."))

            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: StudioSpace.s2) {
                        ForEach(Self.tries, id: \.self) { word in
                            StudioChip(word) { search.query = word }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } header: {
                Text("Try")
            }
            .studioClearRow()

            Section("Go to") {
                ForEach(Self.destinations) { destination in
                    Button {
                        router.open(destination)
                    } label: {
                        SearchRowLabel(title: destination.title,
                                       detail: destination.group.title,
                                       systemImage: destination.systemImage)
                    }
                }
            }
            .studioRowBackground()

            Section("Create") {
                ForEach(CreateAction.featured) { action in
                    Button {
                        app.composer = action.composer
                    } label: {
                        SearchRowLabel(title: action.title, detail: action.blurb, systemImage: action.systemImage)
                    }
                }
            }
            .studioRowBackground()
        }
        .studioList()
    }
}

#if DEBUG
#Preview("Search, no query") {
    let app = AppModel.preview()
    return SearchScreen()
        .environment(app)
        .environment(QuickSearchModel(client: app.client))
        .environment(ShellRouter())
}
#endif
