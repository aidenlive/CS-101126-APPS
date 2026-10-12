import SwiftUI

/*
 Composition primitives — the arrangement layer.

 The standardization carried colour, type and components across and left
 this behind, which is why token-correct screens still read flat: every
 element arrived at the same weight, and the system had no opinion at
 all about photography despite the spec asking for one.

 What lives here:

   StudioRemoteImage      async image with the system's own placeholder
                          and failure states — never a raw AsyncImage
   StudioProtectionScrim  the gradient that makes text on imagery legal
   StudioHero             THE focal element: full-bleed image, scrim,
                          light-ink two-tone title, optional affordance
   .studioOnImage()       the ink contract for anything over a photo

 Everything reads its numbers from `StudioComposition`, generated from
 the token file, so the web `--hero-h-*` / `--scrim-*` values and these
 cannot drift.
 */

// MARK: - Remote image

/// Async imagery with the states the system specifies: a `surface-3`
/// well while loading, a muted glyph on failure. Views should reach for
/// this rather than `AsyncImage` so all three states stay consistent.
public struct StudioRemoteImage: View {
    private let url: URL?
    private let contentMode: ContentMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    public var body: some View {
        AsyncImage(
            url: url,
            transaction: Transaction(animation: StudioAnimation.resolve(StudioAnimation.reveal, reduceMotion: reduceMotion))
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder(systemImage: "photo")
            case .empty:
                placeholder(systemImage: nil)
            @unknown default:
                placeholder(systemImage: nil)
            }
        }
        .accessibilityHidden(true)
    }

    private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Color.studioSurface3
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.studioText4)
            }
        }
    }
}

// MARK: - Protection scrim

/// The gradient that sits between a photograph and the text on it.
///
/// Not decoration — the contrast contract. Light ink over an unknown
/// image is unreadable often enough that the system requires this
/// wherever the two meet, and `StudioHero` applies it for you.
public struct StudioProtectionScrim: View {
    private let intensity: CGFloat
    private let coverage: CGFloat
    private let edge: UnitPoint

    public init(
        intensity: CGFloat = StudioComposition.scrimIntensity,
        coverage: CGFloat = StudioComposition.scrimCoverage,
        edge: UnitPoint = .bottom
    ) {
        self.intensity = intensity
        self.coverage = coverage
        self.edge = edge
    }

    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: StudioComposition.scrimInk.opacity(intensity), location: 0),
                .init(color: StudioComposition.scrimInk.opacity(intensity * 0.45), location: coverage * 0.45),
                .init(color: .clear, location: coverage),
            ],
            startPoint: edge,
            endPoint: edge == .bottom ? .top : .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// The ink contract for content sitting on imagery: light ink in
    /// both themes, because the surface underneath is a photograph and
    /// not a theme surface. `muted` is for meta lines.
    func studioOnImage(muted: Bool = false) -> some View {
        foregroundStyle(muted
                        ? StudioComposition.scrimOnImageInkMuted
                        : StudioComposition.scrimOnImageInk)
    }
}

// MARK: - Hero

/// The focal moment. One per screen.
///
/// A screen earns a hero when it has something worth looking at; the
/// rest of the page then sits at `feature` or `dense` weight beneath
/// it. Two heroes on one screen means neither is the focus, and a page
/// of uniformly weighted cards — the v1.7 Dashboard — means the screen
/// never made a choice at all.
///
///     StudioHero(
///         imageURL: item.imageURL,
///         kicker: "Featured · Pattern",
///         title: "A working", accent: "collection.",
///         meta: "Sheet · 4 detents · May 21",
///         affordance: "Inspect"
///     ) { open(item) }
public struct StudioHero<Image_: View, Trailing: View>: View {
    private let image: Image_
    private let kicker: String?
    private let title: String
    private let accent: String
    private let meta: String?
    private let affordance: String?
    private let action: (() -> Void)?
    private let trailing: Trailing

    @Environment(\.studioViewport) private var viewport
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1

    /// The image is supplied as a view rather than a URL so the hero
    /// works with bundled assets, remote imagery, or a generated
    /// surface without the system prescribing where pictures come from.
    public init(
        kicker: String? = nil,
        title: String,
        accent: String,
        meta: String? = nil,
        affordance: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder image: () -> Image_,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.image = image()
        self.kicker = kicker
        self.title = title
        self.accent = accent
        self.meta = meta
        self.affordance = affordance
        self.action = action
        self.trailing = trailing()
    }

    private var height: CGFloat {
        switch viewport {
        case .compact: return StudioComposition.heroHeightCompact
        case .medium:  return StudioComposition.heroHeightMedium
        default:       return StudioComposition.heroHeightWide
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous)

        /* The text sets the height, with the token height as the floor: at
           the largest Dynamic Type sizes the hero grows rather than
           clipping its title. The image and scrim fill whatever results. */
        let surface = heroText
            .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
            .background {
                ZStack {
                    image
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    StudioProtectionScrim()
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
            .studioElevation(.raised)

        if let action {
            Button(action: action) { surface }
                .buttonStyle(StudioPressStyle(scale: 0.99))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
        } else {
            surface
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s3) {
            if let kicker {
                HStack(spacing: StudioSpace.s2) {
                    Circle()
                        .fill(Color.studioAccent)
                        .frame(width: 5, height: 5)
                    Text(kicker)
                        .studioText(.kicker)
                        .studioOnImage()
                }
            }

            /* The two-tone title, tuned for imagery: white lead plus a
               translucent serif accent. The themed accent ink is a muted
               grey and would vanish against a photograph, so this is the
               one place the pairing is restated rather than reused. */
            (
                Text(title)
                    .font(.custom(StudioFontFamily.display, fixedSize: displaySize))
                    .foregroundColor(StudioComposition.scrimOnImageInk)
                + Text(accent)
                    .font(.custom(StudioFontFamily.serif, fixedSize: displaySize))
                    .italic()
                    .foregroundColor(StudioComposition.scrimOnImageInkMuted)
            )
            .tracking(-0.9)
            .fixedSize(horizontal: false, vertical: true)

            if let meta {
                Text(meta)
                    .studioText(.meta)
                    .studioOnImage(muted: true)
            }

            HStack(spacing: StudioSpace.s3) {
                if let affordance {
                    HStack(spacing: StudioSpace.s2) {
                        Text(affordance).studioText(.uiSm)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.studioAccentInk)
                    .padding(.vertical, StudioSpace.s2)
                    .padding(.horizontal, StudioSpace.s4)
                    .background(Color.studioAccent, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.studioAccentLine, lineWidth: 0.5))
                }
                trailing
            }
            .padding(.top, StudioSpace.s2)
        }
        .padding(viewport == .compact ? StudioSpace.s5 : StudioSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scaled once, through `@ScaledMetric`, and applied with `fixedSize:`
    /// — the same single-scaling rule as `.studioText`.
    private var displaySize: CGFloat {
        (viewport == .compact ? 34 : 44) * typeScale
    }

    private var accessibilityLabel: String {
        [kicker, title + accent, meta]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

public extension StudioHero where Trailing == EmptyView {
    init(
        kicker: String? = nil,
        title: String,
        accent: String,
        meta: String? = nil,
        affordance: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder image: () -> Image_
    ) {
        self.init(
            kicker: kicker, title: title, accent: accent,
            meta: meta, affordance: affordance, action: action,
            image: image, trailing: { EmptyView() }
        )
    }
}

public extension StudioHero where Image_ == StudioRemoteImage, Trailing == EmptyView {
    /// Convenience for the remote case.
    init(
        imageURL: URL?,
        kicker: String? = nil,
        title: String,
        accent: String,
        meta: String? = nil,
        affordance: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.init(
            kicker: kicker, title: title, accent: accent,
            meta: meta, affordance: affordance, action: action,
            image: { StudioRemoteImage(url: imageURL) },
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Entrance

/// The staggered entrance used on page heads and heroes: an 8pt rise
/// and a fade on the `reveal` curve, routed through the single
/// reduce-motion gate so it disappears cleanly when asked.
public struct StudioEntrance: ViewModifier {
    private let delay: Double
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(delay: Double = 0) {
        self.delay = delay
    }

    public func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(
                    StudioAnimation.resolve(StudioAnimation.reveal, reduceMotion: reduceMotion)?
                        .delay(delay)
                ) {
                    appeared = true
                }
            }
    }
}

public extension View {
    func studioEntrance(delay: Double = 0) -> some View {
        modifier(StudioEntrance(delay: delay))
    }
}
