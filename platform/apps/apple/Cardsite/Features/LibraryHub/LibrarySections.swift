import SwiftUI
import StudioKit
import CardsiteKit

// The Library hub's parts, top to bottom: the Recently edited shelf, then
// the type rows grouped Content / Organize / Insights. Music Library's type
// rows crossed with Photos' collection shelves, on opaque Studio surfaces.
// Section heads are quiet (`StudioSectionHeader`) and the type rows are
// Studio's neutral catalogue rows: the page head is the one focal element,
// and the accent is kept for a view's one primary action.

// MARK: - Groups

/// The hub's groups of type rows. Inbox, Workspace, Preferences and Account
/// live in the account sheet instead.
enum LibraryGroup: String, CaseIterable, Identifiable, Sendable {
    case content, organize, insights

    var id: String { rawValue }

    /// The section header's label (an uppercase style: a word, not a
    /// sentence).
    var title: String {
        switch self {
        case .content: return String(localized: "Content")
        case .organize: return String(localized: "Organize")
        case .insights: return String(localized: "Insights")
        }
    }

    /// The section header's note, in sentence case.
    var note: String {
        switch self {
        case .content: return String(localized: "Everything you publish.")
        case .organize: return String(localized: "Keep it tidy.")
        case .insights: return String(localized: "See what’s working.")
        }
    }

    var destinations: [AppDestination] {
        switch self {
        case .content:
            return [.pages, .qrCodes, .vcards, .events, .paymentLinks, .fileLinks,
                    .staticPages, .splashPages, .uploads, .data]
        case .organize:
            return [.projects, .domains, .pixels]
        case .insights:
            return [.statistics, .activity]
        }
    }
}

extension AppDestination {
    /// One line under a hub row's title, in the web's words where it has them.
    var libraryBlurb: String {
        if let resourceKind { return resourceKind.blurb }
        switch self {
        case .pages: return String(localized: "Link-in-bio pages, built from blocks.")
        case .qrCodes: return String(localized: "Scannable codes, fully styled.")
        case .uploads: return String(localized: "Images and files you’ve added.")
        case .data: return String(localized: "Form submissions from your pages.")
        case .projects: return String(localized: "Group resources into color-coded projects.")
        case .domains: return String(localized: "Branded addresses for your links.")
        case .pixels: return String(localized: "Tracking pixels for retargeting.")
        case .statistics: return String(localized: "Clicks and visitors across the workspace.")
        case .activity: return String(localized: "Sign-ins and changes to your account.")
        default: return group.title
        }
    }
}

// MARK: - Recently edited

/// "Recently edited": a snapping shelf of resource tiles on every width;
/// a stack of them at accessibility text sizes, where tiles side by side
/// would truncate every address.
struct LibraryRecentSection: View {
    let model: LibraryModel
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.studioViewport) private var viewport

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            PageSectionHead(String(localized: "Recently edited"),
                            note: String(localized: "Your latest work, newest first."))

            switch model.state {
            case .idle, .loading:
                tiles(LibraryModel.Snapshot.sample.recent)
                    .redacted(reason: .placeholder)
                    .disabled(true)
                    .loadingAccessibility(true)
            case .failed(let error):
                StudioCard {
                    InlineErrorState(error: error) { [model] in await model.refresh() }
                }
            case .loaded(let snapshot) where snapshot.recent.isEmpty:
                StudioCard {
                    StudioEmptyState(
                        systemImage: "sparkles",
                        title: String(localized: "Nothing edited yet"),
                        message: String(localized: "What you create or change shows up here, newest first."),
                        compact: true
                    ) {
                        StudioButton(String(localized: "New Short Link"), systemImage: "plus", variant: .outline) {
                            app.composer = .link
                        }
                    }
                }
            case .loaded(let snapshot):
                tiles(snapshot.recent)
            }
        }
    }

    @ViewBuilder
    private func tiles(_ resources: [Resource]) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: StudioSpace.s3) {
                ForEach(resources) { resource in
                    tile(resource)
                }
            }
        } else {
            SnapShelf {
                ForEach(resources) { resource in
                    tile(resource)
                        .containerRelativeFrame(.horizontal, count: columns.count, span: columns.span,
                                                spacing: StudioSpace.s3)
                }
            }
        }
    }

    /// Two and a bit tiles on iPhone, so the shelf announces it scrolls;
    /// four on iPad and Mac.
    private var columns: (count: Int, span: Int) {
        viewport == .compact ? (count: 9, span: 4) : (count: 4, span: 1)
    }

    private func tile(_ resource: Resource) -> some View {
        ResourceOpenLink(resource: resource) {
            LibraryRecentTile(resource: resource)
        }
        .contextMenu { ResourceActions(resource: resource) }
    }
}

/// A recent resource as a tile: its type glyph and clicks, then the
/// address (two lines, losing its middle rather than its slug), then the
/// type and when it was edited.
struct LibraryRecentTile: View {
    @Environment(AppModel.self) private var app
    let resource: Resource

    private var info: ResourceKindInfo { resource.kindInfo }

    private var edited: Text {
        guard let date = resource.updatedAt ?? resource.createdAt else { return Text(info.title) }
        return Text(info.title) + Text(verbatim: " · ") + Text(date, format: .relative(presentation: .named))
    }

    var body: some View {
        StudioCard(hover: true) {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                HStack(alignment: .center, spacing: StudioSpace.s2) {
                    RowGlyphTile(systemImage: info.systemImage, isActive: resource.isEnabled)
                    Spacer(minLength: StudioSpace.s2)
                    Text(resource.clicks.figure)
                        .monospacedDigit()
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .accessibilityLabel(Text("\(resource.clicks) clicks"))
                }
                Spacer(minLength: StudioSpace.s2)
                Text(verbatim: app.addresses.display(for: resource.slug))
                    .studioText(.ui)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                edited
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Type rows

/// One group: the quiet section header, then its rows on one flush card
/// with 0.5pt hairlines inset to the text, past the glyph tile.
struct LibraryGroupSection: View {
    let group: LibraryGroup
    let summary: DashboardSummary?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = LibraryTypeRow.glyphBase

    /// Row padding, the tile and the gap after it; flush at accessibility
    /// sizes, where the row stacks under its tile.
    private var dividerInset: CGFloat {
        typeSize.isAccessibilitySize ? StudioSpace.s4 : StudioSpace.s4 + glyphSide + StudioSpace.s4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            PageSectionHead(group.title, note: group.note)

            StudioCard(flush: true) {
                VStack(spacing: 0) {
                    ForEach(Array(group.destinations.enumerated()), id: \.element) { index, destination in
                        LibraryTypeLink(destination: destination,
                                        count: summary.flatMap { LibraryModel.count(for: destination, in: $0) })
                        if index < group.destinations.count - 1 {
                            Rectangle()
                                .fill(Color.studioBorder)
                                .frame(height: 0.5)
                                .padding(.leading, dividerInset)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

/// A row that opens its destination: its stack-free view, pushed onto
/// Library's stack.
struct LibraryTypeLink: View {
    @Environment(ShellRouter.self) private var router
    let destination: AppDestination
    let count: Int?

    var body: some View {
        Button {
            router.showFromLibrary(destination)
        } label: {
            LibraryTypeRow(destination: destination, count: count)
        }
        .buttonStyle(StudioPressStyle(scale: 0.99))
        .accessibilityIdentifier(destination.navIdentifier)
    }
}

/// Studio's catalogue row: the neutral glyph tile (surface, secondary
/// ink, never the accent), name and a line about it, the count in `.mono`,
/// a chevron. At accessibility sizes the count moves under the name so
/// nothing truncates.
struct LibraryTypeRow: View {
    let destination: AppDestination
    let count: Int?

    /// The catalogue tile's side before Dynamic Type scales it.
    nonisolated static let glyphBase: CGFloat = StudioLayout.tapTarget

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = LibraryTypeRow.glyphBase

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: StudioSpace.s4) {
            Image(systemName: destination.systemImage)
                .imageScale(.large)
                .foregroundStyle(Color.studioText2)
                .frame(width: glyphSide, height: glyphSide)
                .background(Color.studioSurface3,
                            in: RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(destination.title)
                    .studioText(.ui)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.studioText)
                Text(destination.libraryBlurb)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)
                if typeSize.isAccessibilitySize, let count {
                    countText(count)
                }
            }

            Spacer(minLength: StudioSpace.s2)

            if !typeSize.isAccessibilitySize, let count {
                countText(count)
            }
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(Color.studioText4)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, StudioSpace.s4)
        .padding(.vertical, StudioComposition.rhythmDetailRow)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func countText(_ count: Int) -> some View {
        Text(count.grouped)
            .studioText(.mono)
            .foregroundStyle(Color.studioText3)
            .accessibilityLabel(Text("\(count) items"))
    }
}
