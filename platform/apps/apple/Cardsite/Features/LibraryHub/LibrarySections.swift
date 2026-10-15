import SwiftUI
import StudioKit
import CardsiteKit

// The Library hub's parts, top to bottom: the Recently edited shelf, then
// the type rows grouped Content / Organize / Insights. Music Library's type
// rows crossed with Photos' collection shelves, on opaque Studio surfaces.

// MARK: - Groups

/// The hub's groups of type rows. Inbox, Workspace, Preferences and Account
/// live in the account sheet instead.
enum LibraryGroup: String, CaseIterable, Identifiable, Sendable {
    case content, organize, insights

    var id: String { rawValue }

    var kicker: String {
        switch self {
        case .content: return String(localized: "Content")
        case .organize: return String(localized: "Organize")
        case .insights: return String(localized: "Insights")
        }
    }

    /// The two-tone section title: lead, then the serif accent.
    var title: (lead: String, accent: String) {
        switch self {
        case .content: return (String(localized: "Everything you "), String(localized: "publish."))
        case .organize: return (String(localized: "Keep it "), String(localized: "tidy."))
        case .insights: return (String(localized: "See what’s "), String(localized: "working."))
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
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            PageSectionHead(kicker: String(localized: "Recently edited"),
                            title: String(localized: "Your latest "),
                            accent: String(localized: "work."))

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

/// One group: the section head, then its rows on one opaque card.
struct LibraryGroupSection: View {
    let group: LibraryGroup
    let summary: DashboardSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            PageSectionHead(kicker: group.kicker, title: group.title.lead, accent: group.title.accent)

            StudioCard(flush: true) {
                VStack(spacing: 0) {
                    ForEach(Array(group.destinations.enumerated()), id: \.element) { index, destination in
                        LibraryTypeLink(destination: destination,
                                        count: summary.flatMap { LibraryModel.count(for: destination, in: $0) })
                        if index < group.destinations.count - 1 {
                            Divider()
                                .overlay(Color.studioBorder)
                                .padding(.leading, StudioSpace.s16)
                        }
                    }
                }
            }
        }
    }
}

/// A row that opens its destination: pushed onto Library's stack, or (Pages
/// and QR Codes, which own their navigation) opened as their own tab.
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

/// Glyph tile, name and a line about it, the count, a chevron. At
/// accessibility sizes the count moves under the name so nothing truncates.
struct LibraryTypeRow: View {
    let destination: AppDestination
    let count: Int?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = StudioSpace.s10

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: StudioSpace.s4) {
            Image(systemName: destination.systemImage)
                .imageScale(.medium)
                .foregroundStyle(Color.studioAccentLine)
                .frame(width: glyphSide, height: glyphSide)
                .background(Color.studioAccentSoft,
                            in: RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
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
        .padding(.horizontal, StudioSpace.s5)
        .padding(.vertical, StudioSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func countText(_ count: Int) -> some View {
        Text(count.grouped)
            .monospacedDigit()
            .studioText(.ui)
            .foregroundStyle(Color.studioText3)
            .accessibilityLabel(Text("\(count) items"))
    }
}
