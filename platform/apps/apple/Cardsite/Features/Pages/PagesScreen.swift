import SwiftUI
import Observation
import StudioKit
import CardsiteKit

/// Bio pages: listed for sharing and opening. Editing their 85 block types
/// stays on the web for this release (see docs/launch/native-apple.md).
@MainActor
@Observable
final class PagesModel {
    let list: PagedListModel<Resource>

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in } {
        didSet { list.onError = onError }
    }

    init(client: APIClient) {
        self.list = PagedListModel { page in try await client.bioPages(page: page) }
    }
}

struct PagesScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(PagesModel.self) private var model

    var body: some View {
        NavigationStack {
            ListStateView(
                state: model.list.state,
                empty: .init(
                    systemImage: "person.crop.square",
                    title: String(localized: "No pages yet"),
                    message: String(localized: "Bio pages you build on cardsite.com appear here, ready to share.")
                ),
                retry: { [list = model.list] in await list.refresh() }
            ) { pages in
                List {
                    if let error = model.list.refreshError {
                        RefreshErrorBanner(error: error) { model.list.dismissRefreshError() }
                            .listRowSeparator(.hidden)
                    }
                    ForEach(pages) { page in
                        PageRow(page: page)
                    }
                    if model.list.hasMore {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .task(id: model.list.items.count) { [list = model.list] in await list.loadMore() }
                    }
                }
                .refreshable { await model.list.refresh() }
            }
            .navigationTitle("Pages")
        }
        .task { [list = model.list] in await list.loadIfNeeded() }
    }
}

private struct PageRow: View {
    @Environment(AppModel.self) private var app
    let page: Resource

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: app.addresses.display(for: page.slug))
                    .studioText(.ui)
                    .lineLimit(1)
                HStack(spacing: StudioSpace.s2) {
                    Label(page.clicks.grouped, systemImage: "eye")
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(page.clicks) views"))
                    if !page.isEnabled {
                        StudioStatusPill(String(localized: "Off"), tone: .neutral)
                    }
                }
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
            }
            Spacer()
            if let url = app.addresses.url(for: page.slug) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share \(app.addresses.display(for: page.slug))")
            }
        }
        .contextMenu {
            if let url = app.addresses.url(for: page.slug) {
                Button { Pasteboard.copy(url.absoluteString) } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
                Link(destination: url) { Label("Open Page", systemImage: "safari") }
            }
            if let card = app.addresses.cardURL(for: page.slug) {
                Link(destination: card) {
                    Label("View Card", systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
            }
        }
    }
}
