import SwiftUI
import StudioKit
import CardsiteKit

/// Home's search results on iPhone: destinations, create actions and the
/// workspace's links, in a native list. Links push their detail in Home's
/// stack.
struct QuickSearchResults: View {
    @Environment(AppModel.self) private var app
    @Environment(QuickSearchModel.self) private var search
    @Environment(ShellRouter.self) private var router

    var body: some View {
        List {
            if !search.destinations.isEmpty {
                Section("Go to") {
                    ForEach(search.destinations) { destination in
                        Button {
                            router.open(destination)
                        } label: {
                            SearchRowLabel(title: destination.title,
                                           detail: destination.group.title,
                                           systemImage: destination.systemImage)
                        }
                    }
                }
            }

            if !search.actions.isEmpty {
                Section("Create") {
                    ForEach(search.actions) { action in
                        Button {
                            app.composer = action.composer
                        } label: {
                            SearchRowLabel(title: action.title, detail: action.blurb, systemImage: action.systemImage)
                        }
                    }
                }
            }

            if search.searchesLinks {
                Section {
                    linkRows
                } header: {
                    HStack(spacing: StudioSpace.s2) {
                        Text("Links")
                        if search.isSearchingLinks {
                            ProgressView().controlSize(.mini)
                                .accessibilityLabel("Searching links")
                        }
                    }
                }
            }
        }
        .overlay {
            if search.hasNoResults, !search.searchesLinks || search.links.value != nil {
                ContentUnavailableView.search(text: search.trimmedQuery)
            }
        }
        .task(id: search.query) { [search] in await search.searchLinks() }
    }

    @ViewBuilder
    private var linkRows: some View {
        switch search.links {
        case .failed(let error):
            Label {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(error == .offline ? String(localized: "You're offline") : String(localized: "Couldn't search links"))
                    Text(error.localizedDescription)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            } icon: {
                Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
            }
        case .loaded(let links) where links.isEmpty && !search.isSearchingLinks:
            Text("No links match “\(search.trimmedQuery)”")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        case .loaded(let links):
            ForEach(links) { link in
                NavigationLink(value: link) {
                    SearchLinkLabel(link: link)
                }
            }
        case .idle, .loading:
            Text("Searching…")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
    }
}

/// A destination or action row: glyph, title, one line of detail.
struct SearchRowLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(title)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                Text(detail)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.studioAccentLine)
        }
    }
}

/// A short link in results: its address, where it goes, its clicks.
struct SearchLinkLabel: View {
    @Environment(AppModel.self) private var app
    let link: Resource

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Label {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text(verbatim: app.addresses.display(for: link.slug))
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: link.destination ?? "")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } icon: {
                Image(systemName: "link")
                    .foregroundStyle(Color.studioAccentLine)
            }
            Spacer(minLength: StudioSpace.s2)
            Text(link.clicks.figure)
                .monospacedDigit()
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                .accessibilityLabel(Text("\(link.clicks) clicks"))
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Search results") {
    let app = AppModel.preview()
    let search = QuickSearchModel(client: app.client)
    search.query = "acc"
    return NavigationStack {
        QuickSearchResults()
    }
    .environment(app)
    .environment(search)
    .environment(ShellRouter())
}
#endif
