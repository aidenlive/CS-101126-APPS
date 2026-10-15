import SwiftUI
import StudioKit

/// A horizontal shelf that snaps to its items: Library's Recently edited
/// tiles and, on iPhone, Home's quick-create tiles.
///
/// It bleeds to the page's edges (the page pads by the viewport's content
/// padding; the shelf undoes that and puts it back as content margins), so
/// the next item peeks in at the trailing edge and the first one lines up
/// with the page's text. Items size themselves with
/// `.containerRelativeFrame(.horizontal, count:span:spacing:)` and should
/// fill their height (`.frame(maxHeight: .infinity)`), so every card in a
/// shelf is as tall as the tallest.
struct SnapShelf<Content: View>: View {
    var spacing: CGFloat = StudioSpace.s3
    @ViewBuilder var content: () -> Content

    @Environment(\.studioViewport) private var viewport

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                content()
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, viewport.contentPadding, for: .scrollContent)
        // Card hover lifts and focus rings aren't cut at the shelf's edge.
        .scrollClipDisabled()
        .padding(.horizontal, -viewport.contentPadding)
    }
}

#if DEBUG
#Preview("Shelf") {
    ScrollView {
        SnapShelf {
            ForEach(0..<5) { index in
                StudioCard {
                    Text("Card \(index + 1)")
                        .studioText(.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .containerRelativeFrame(.horizontal, count: 6, span: 5, spacing: StudioSpace.s3)
            }
        }
        .padding(.horizontal, StudioSpace.s5)
    }
    .background(Color.studioBg)
}
#endif
