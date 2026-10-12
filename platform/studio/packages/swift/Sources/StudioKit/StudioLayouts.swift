import SwiftUI

/*
 Layout primitives.

 The web layer's `.l-split`, `.l-switcher` and `.l-frame` — the three
 that had no SwiftUI equivalent. Container, Stack, Cluster and Grid map
 onto VStack/HStack/LazyVGrid well enough that wrapping them would be
 ceremony; these three do NOT, because each one makes a decision based
 on the space it is given, which is `Layout`-protocol territory.

 All three follow the CSS behaviour, not an approximation of it:

   Split     two children on one row at a fraction; stacks when the
             row would drop either side under its minimum.
   Switcher  N children on one row; ALL of them wrap to a column the
             moment any one would fall under the threshold.
   Frame     a fixed-ratio media well that clips its content.
 */

// MARK: - Split

/// Two children side by side at `fraction`, stacking vertically when
/// horizontal space would push either side below `minSide`.
///
///     StudioSplit(fraction: 0.38) {
///         SidebarPane()
///         DetailPane()
///     }
public struct StudioSplit: Layout {
    private let fraction: CGFloat
    private let spacing: CGFloat
    private let minSide: CGFloat

    public init(
        fraction: CGFloat = 0.5,
        spacing: CGFloat = StudioSpace.s5,
        minSide: CGFloat = 280
    ) {
        self.fraction = min(max(fraction, 0.1), 0.9)
        self.spacing = spacing
        self.minSide = minSide
    }

    private func isStacked(in width: CGFloat) -> Bool {
        let usable = width - spacing
        return usable * fraction < minSide || usable * (1 - fraction) < minSide
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }
        let width = proposal.width ?? minSide * 2 + spacing

        if isStacked(in: width) {
            let a = subviews[0].sizeThatFits(.init(width: width, height: nil))
            let b = subviews[1].sizeThatFits(.init(width: width, height: nil))
            return CGSize(width: width, height: a.height + spacing + b.height)
        }
        let wA = (width - spacing) * fraction
        let wB = (width - spacing) * (1 - fraction)
        let a = subviews[0].sizeThatFits(.init(width: wA, height: nil))
        let b = subviews[1].sizeThatFits(.init(width: wB, height: nil))
        return CGSize(width: width, height: max(a.height, b.height))
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else {
            subviews.first?.place(at: bounds.origin, proposal: proposal)
            return
        }

        if isStacked(in: bounds.width) {
            let a = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
            subviews[0].place(
                at: bounds.origin,
                proposal: .init(width: bounds.width, height: a.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + a.height + spacing),
                proposal: .init(width: bounds.width, height: nil)
            )
            return
        }

        let wA = (bounds.width - spacing) * fraction
        let wB = (bounds.width - spacing) * (1 - fraction)
        subviews[0].place(
            at: bounds.origin,
            proposal: .init(width: wA, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + wA + spacing, y: bounds.minY),
            proposal: .init(width: wB, height: bounds.height)
        )
    }
}

// MARK: - Switcher

/// N children sharing one row equally; the whole set wraps to a column
/// the moment any child would fall under `threshold`. All-or-nothing,
/// exactly like the CSS switcher — a half-wrapped row is the failure
/// mode this exists to prevent.
///
///     StudioSwitcher(threshold: 220) {
///         StatCard(…); StatCard(…); StatCard(…)
///     }
public struct StudioSwitcher: Layout {
    private let threshold: CGFloat
    private let spacing: CGFloat

    public init(threshold: CGFloat = 220, spacing: CGFloat = StudioSpace.s4) {
        self.threshold = threshold
        self.spacing = spacing
    }

    private func isColumn(count: Int, in width: CGFloat) -> Bool {
        guard count > 1 else { return false }
        let per = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        return per < threshold
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? threshold * CGFloat(subviews.count)
        guard !subviews.isEmpty else { return .zero }

        if isColumn(count: subviews.count, in: width) {
            var height: CGFloat = 0
            for (i, sub) in subviews.enumerated() {
                height += sub.sizeThatFits(.init(width: width, height: nil)).height
                if i < subviews.count - 1 { height += spacing }
            }
            return CGSize(width: width, height: height)
        }
        let per = (width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        let tallest = subviews
            .map { $0.sizeThatFits(.init(width: per, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: tallest)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        if isColumn(count: subviews.count, in: bounds.width) {
            var y = bounds.minY
            for sub in subviews {
                let h = sub.sizeThatFits(.init(width: bounds.width, height: nil)).height
                sub.place(
                    at: CGPoint(x: bounds.minX, y: y),
                    proposal: .init(width: bounds.width, height: h)
                )
                y += h + spacing
            }
            return
        }

        let per = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        var x = bounds.minX
        for sub in subviews {
            sub.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: .init(width: per, height: bounds.height)
            )
            x += per + spacing
        }
    }
}

// MARK: - Frame

/// A fixed-ratio media well: `surface-3` fill, `lg` radius, content
/// scaled to fill and clipped. The shape every thumbnail, cover and
/// placeholder in the system uses.
///
///     StudioFrame(ratio: 4/3) { AsyncImage(url: cover) }
///     StudioFrame { Text("Aa").studioText(.display).studioMuted() }
public struct StudioFrame<Content: View>: View {
    private let ratio: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    public init(
        ratio: CGFloat = 16 / 9,
        cornerRadius: CGFloat = StudioRadius.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.ratio = ratio
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Color.studioSurface3
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                content
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
    }
}
