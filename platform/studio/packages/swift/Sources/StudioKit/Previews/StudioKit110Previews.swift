/* ============================================================
   Previews for the components ported from Studio 1.10.

   DEBUG only. Fixed sample data, `.constant` bindings where a
   binding is enough, no networking.
   ============================================================ */

#if DEBUG
import SwiftUI

private enum PreviewFilter: Hashable { case all, live, paused }
private enum PreviewMode: Hashable { case list, grid }
private enum PreviewTab: Hashable { case home, links, pages }

#Preview("CollectionBar") {
    StudioCollectionBar(
        filters: [
            StudioSegment(value: PreviewFilter.all, label: "All"),
            StudioSegment(value: PreviewFilter.live, label: "Live"),
            StudioSegment(value: PreviewFilter.paused, label: "Paused"),
        ],
        filterCounts: [.all: 42, .live: 39, .paused: 3],
        filter: .constant(.all),
        searchPlaceholder: "Search links",
        search: .constant(""),
        sortOptions: ["Newest", "Most clicks"],
        sort: .constant("Newest"),
        viewModes: [
            StudioSegment(value: PreviewMode.list, label: "List", systemImage: "list.bullet"),
            StudioSegment(value: PreviewMode.grid, label: "Grid", systemImage: "square.grid.2x2"),
        ],
        viewMode: .constant(.list)
    )
    .padding()
    .background(Color.studioBg)
}

#Preview("Layouts") {
    VStack(spacing: StudioSpace.s6) {
        StudioSwitcher(threshold: 140) {
            StudioCard { Text("Clicks").studioText(.ui) }
            StudioCard { Text("Visitors").studioText(.ui) }
            StudioCard { Text("Scans").studioText(.ui) }
        }
        StudioSplit(fraction: 0.4, minSide: 120) {
            StudioCard { Text("Leading").studioText(.ui) }
            StudioCard { Text("Trailing").studioText(.ui) }
        }
        StudioFrame(ratio: 16 / 9) {
            Image(systemName: "photo").foregroundStyle(Color.studioText4)
        }
    }
    .padding()
    .background(Color.studioBg)
}

#Preview("Hero") {
    StudioHero(
        kicker: "Top performer",
        title: "Spring ",
        accent: "launch.",
        meta: "1,204 clicks · 7 days",
        affordance: "Open",
        image: {
            LinearGradient(colors: [.studioViz1, .studioViz2], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    )
    .padding()
    .background(Color.studioBg)
}

#Preview("Account") {
    VStack(alignment: .leading, spacing: StudioSpace.s4) {
        HStack(spacing: StudioSpace.s3) {
            StudioAvatar(name: "Daria Moss", size: .sm)
            StudioAvatar(name: "Daria Moss", size: .md, presence: .online)
            StudioAvatar(name: "Daria Moss", size: .lg, presence: .away)
        }
        StudioAccountButton(name: "Daria Moss") {}
        StudioAccountSheet(
            config: StudioAccountConfig(name: "Daria Moss", email: "daria@example.com") {
                StudioAccountRow(systemImage: "gearshape", title: "Settings") {}
            },
            onSignOut: {}
        )
    }
    .padding()
    .background(Color.studioBg)
}

#Preview("Dock") {
    StudioDock(
        selection: .constant(PreviewTab.home),
        items: [
            StudioDockItem(tag: PreviewTab.home, title: "Home", systemImage: "house"),
            StudioDockItem(tag: PreviewTab.links, title: "Links", systemImage: "link", selectedSystemImage: "link"),
            StudioDockItem(tag: PreviewTab.pages, title: "Pages", systemImage: "doc.richtext"),
        ],
        onSearch: {},
        actionTitle: "New link",
        onAction: {}
    )
    .padding()
    .background(Color.studioBg)
}

#Preview("Banner, dismissible") {
    StudioBanner(lead: "Offline.", message: "Showing what was loaded last.", tone: .warning) {}
        .padding()
        .background(Color.studioBg)
}

#Preview("Glass, tinted") {
    HStack(spacing: StudioSpace.s3) {
        Image(systemName: "plus")
            .foregroundStyle(Color.studioAccentInk)
            .frame(width: StudioLayout.dockAction, height: StudioLayout.dockAction)
            .studioGlass(in: Circle(), tint: .studioAccent, interactive: true)
        Text("Chrome")
            .studioText(.ui)
            .padding(.horizontal, StudioSpace.s4)
            .frame(minHeight: StudioLayout.pillHeight)
            .studioGlass()
    }
    .padding()
    .background(Color.studioBg)
}

#Preview("Chart palette") {
    HStack(spacing: StudioSpace.s1) {
        ForEach(Array(Color.studioVizCategorical.enumerated()), id: \.offset) { _, colour in
            RoundedRectangle(cornerRadius: StudioRadius.xs).fill(colour).frame(height: 40)
        }
        RoundedRectangle(cornerRadius: StudioRadius.xs).fill(Color.studioVizHighlight).frame(height: 40)
        RoundedRectangle(cornerRadius: StudioRadius.xs).fill(Color.studioVizOther).frame(height: 40)
    }
    .padding()
    .background(Color.studioSurface)
}

#Preview("Editor shell") {
    StudioCanvasShell(
        zoomLabel: "100%",
        onZoomIn: {},
        onZoomOut: {},
        tools: {
            StudioToolButton(systemImage: "cursorarrow", label: "Select", isSelected: true) {}
            StudioToolButton(systemImage: "textformat", label: "Text") {}
        },
        inspector: {
            StudioSectionHeader("Block")
            StudioToggleRow("Visible", isOn: .constant(true))
        },
        canvas: {
            ZStack {
                StudioCanvasGrid()
                StudioArtboard { Color.clear.frame(width: 240, height: 320) }
            }
        }
    )
}
#endif
