import SwiftUI

/*
 The collection bar.

 The toolbar band of the Studio heading system: filters · search ·
 sort · view, composed as ONE cohesive band instead of a stack of
 full-width rows. This is the piece the heading system promises —
 "title / description / filter / sort / view / search" holding a
 balanced posture at every width:

   expanded/medium   [chips ………………]  [search → flexes] [sort] [view]
   compact           [chips …………………………………………………… scrolls]
                     [search → flexes]              [sort] [view]

 One rule, no per-device exceptions: the chips row always scrolls
 horizontally, and search always shares its row with sort + view —
 search flexes, controls hug. Progressive disclosure lives in the
 sort control: a menu, closed by default, never a stacked row.
 */
public struct StudioCollectionBar<Filter: Hashable, ViewMode: Hashable>: View {
    private let filters: [StudioSegment<Filter>]
    private let filterCounts: [Filter: Int]
    private let viewModes: [StudioSegment<ViewMode>]
    private let sortOptions: [String]
    private let searchPlaceholder: String

    @Binding private var filter: Filter
    @Binding private var viewMode: ViewMode
    @Binding private var search: String
    @Binding private var sort: String

    @Environment(\.studioViewport) private var viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.studioHaptics) private var haptics

    public init(
        filters: [StudioSegment<Filter>],
        filterCounts: [Filter: Int] = [:],
        filter: Binding<Filter>,
        searchPlaceholder: String = "Search collection",
        search: Binding<String>,
        sortOptions: [String] = [],
        sort: Binding<String> = .constant(""),
        viewModes: [StudioSegment<ViewMode>],
        viewMode: Binding<ViewMode>
    ) {
        self.filters = filters
        self.filterCounts = filterCounts
        self._filter = filter
        self.searchPlaceholder = searchPlaceholder
        self._search = search
        self.sortOptions = sortOptions
        self._sort = sort
        self.viewModes = viewModes
        self._viewMode = viewMode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s3) {
            chipsRow
            controlsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collection controls")
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StudioSpace.s2) {
                ForEach(filters) { segment in
                    StudioChip(
                        segment.label,
                        count: filterCounts[segment.value],
                        isSelected: filter == segment.value
                    ) {
                        guard filter != segment.value else { return }
                        haptics.play(.selection)
                        withAnimation(StudioAnimation.resolve(StudioAnimation.spring, reduceMotion: reduceMotion)) {
                            filter = segment.value
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: StudioSpace.s2) {
            StudioSearchField(text: $search, placeholder: searchPlaceholder)
                .frame(maxWidth: viewport == .compact ? .infinity : 360)

            if !sortOptions.isEmpty {
                Menu {
                    ForEach(sortOptions, id: \.self) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option, systemImage: "checkmark")
                            } else {
                                Text(option)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: StudioLayout.tapTarget, height: StudioLayout.tapTarget)
                        .foregroundStyle(Color.studioText2)
                        .background(Circle().fill(Color.studioSurface))
                        .overlay(Circle().strokeBorder(Color.studioBorder, lineWidth: 0.5))
                        .contentShape(Circle())
                }
                // Our label draws the control, so on macOS the menu must not
                // add a bordered pop-up button and indicator around it.
                .menuStyle(.button)
                .buttonStyle(StudioPressStyle())
                .menuIndicator(.hidden)
                .accessibilityLabel("Sort")
                .accessibilityValue(sort)
            }

            StudioSegmented(
                label: "View",
                selection: $viewMode,
                segments: viewModes,
                iconsOnly: true
            )
            .layoutPriority(1)
        }
    }
}
