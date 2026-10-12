import SwiftUI

/*
 Components.

 The same atoms as the web layer, with the same rules:
 · One accent action per view.
 · Press shrinks, focus rings, hover fills one surface step.
 · Semantic colours only — nothing here reaches into the palette.
 */

// MARK: - Button

public enum StudioButtonVariant {
    /// The one accent action in a view.
    case primary
    /// The default. Transparent until hovered.
    case ghost
    /// A quiet bordered button, for secondary actions on a busy surface.
    case outline
    /// Irreversible actions only, always behind a confirm.
    case destructive
    /// The quiet counterpart to `destructive` (ADR-0033's two-word
    /// system): error ink on a transparent fill, for the row-level
    /// delete that has not yet earned a filled button.
    case danger
}

public struct StudioButton: View {
    private let title: String
    private let systemImage: String?
    private let variant: StudioButtonVariant
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    /// `isLoading` swaps the icon (or leads the title) with a small
    /// spinner and swallows taps, keeping the button's width and tone so
    /// the layout does not jump. A `.disabled(true)` button dims to 45%.
    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: StudioButtonVariant = .ghost,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            HStack(spacing: StudioSpace.s2) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title).studioText(.ui)
            }
            .padding(.horizontal, StudioSpace.s4)
            .frame(minHeight: 40)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(
                Capsule().strokeBorder(border, lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(StudioPressStyle())
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }

    private var foreground: Color {
        switch variant {
        case .primary: return .studioAccentInk
        // Not `.white`: white on dark-theme `studioError` is 3.29:1.
        // `studioSurface` is pure white in light (6.15:1, unchanged) and
        // near-black in dark (5.91:1), so both themes clear AA 4.5:1.
        case .destructive: return .studioSurface
        case .danger: return .studioError
        case .ghost, .outline: return .studioText2
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return .studioAccent
        case .destructive: return .studioError
        case .ghost, .outline, .danger: return .clear
        }
    }

    private var border: Color {
        switch variant {
        case .outline: return .studioBorder
        case .primary, .destructive, .ghost, .danger: return .clear
        }
    }
}

/// Press feedback: everything in Studio shrinks when pressed.
///
/// The spec gives a range of 0.90–0.97 — buttons and chips take 0.96,
/// icon buttons 0.90, the FAB 0.92. Pass the one the component needs.
///
/// With Reduce Motion on, the shrink is replaced by a brief dim, with no spring.
public struct StudioPressStyle: ButtonStyle {
    private let scale: CGFloat

    public init(scale: CGFloat = 0.96) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        StudioPressBody(configuration: configuration, scale: scale)
    }
}

/// `ButtonStyle.makeBody` cannot read the environment directly, so the
/// Reduce Motion check lives in this small view.
private struct StudioPressBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? nil : StudioAnimation.spring, value: configuration.isPressed)
    }
}

// MARK: - Chip

public struct StudioChip: View {
    private let title: String
    private let count: Int?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, count: Int? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s2) {
                Text(title).studioText(.uiSm)
                if let count {
                    Text("\(count)").studioText(.mono)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            // Selected inverts to the primary ink, rather than filling with
            // the accent — the accent is reserved for actions.
            .foregroundStyle(isSelected ? Color.studioSurface : Color.studioText2)
            .background(isSelected ? Color.studioText : Color.studioSurface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? .clear : Color.studioBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(StudioPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Card

public struct StudioCard<Content: View>: View {
    private let content: Content
    private let isFlush: Bool
    private let isHoverable: Bool
    private let isSelected: Bool
    private let radius: CGFloat

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `flush` drops the padding and clips to the corner radius, for
    /// tables and edge-to-edge media — the `.lk-card--flush` variant.
    /// `hover` is the `.lk-card--hover` lift; `selected` the
    /// `.lk-card--selected` accent swap. `radius: StudioRadius.xl` takes
    /// the larger radius for heroes and the account card — the `radius:`
    /// parameter is the API, which is why the parity ledger dispositions
    /// web's `xl` variant `not-planned` (ADR-0051).
    public init(flush: Bool = false, hover: Bool = false, selected: Bool = false, radius: CGFloat = StudioRadius.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isFlush = flush
        self.isHoverable = hover
        self.isSelected = selected
        self.radius = radius
    }

    // `selected` swaps fill and edge to accent — and keeps the accent
    // edge under a hover lift, where `--border-strong` would otherwise
    // take the lime away exactly while the pointer says "this one".
    private var borderColor: Color {
        if isSelected { return .studioAccentLine }
        if isHoverable && isHovering { return .studioBorderStrong }
        return .studioBorder
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // Flush cards hold media and tables that must not paint over the
    // corner radius, so they clip — web's `.lk-card--flush` is the only
    // card rule that sets `overflow: hidden`. A padded card stays
    // unclipped like web's base card: its content cannot reach the
    // corners, and anything it anchors outside itself must not be cut.
    @ViewBuilder private var framed: some View {
        let filled = content
            .padding(isFlush ? 0 : StudioSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isSelected ? Color.studioAccentSoft : Color.studioSurface))
        if isFlush {
            filled.clipShape(shape)
        } else {
            filled
        }
    }

    public var body: some View {
        framed
            .overlay(
                shape.strokeBorder(borderColor, lineWidth: 0.5)
            )
            .studioElevation(isHoverable && isHovering ? .raised : .flat)
            // The lift and shadow apply under a selected accent edge too:
            // web's combined rule overrides only border-color.
            // Reduce Motion keeps the edge and shadow but drops the movement.
            .offset(y: isHoverable && isHovering && !reduceMotion ? -2 : 0)
            .onHover { hovering in
                guard isHoverable else { return }
                isHovering = hovering
            }
    }
}

// MARK: - Status

public enum StudioTone {
    case success, warning, error, info, neutral, accent

    var ink: Color {
        switch self {
        case .success: return .studioSuccess
        case .warning: return .studioWarning
        case .error: return .studioError
        case .info: return .studioInfo
        case .neutral: return .studioText2
        // Lime is a fill, never ink: --accent-line on --accent-soft is
        // 2.81:1 in light. Matches web `.lk-status--accent` (--text ink,
        // lime dot). The dot carries the hue; see `dot`.
        case .accent: return .studioText
        }
    }

    /// The pill's 5pt dot. The tone's ink, except `accent`, whose ink is
    /// neutral and whose dot keeps the lime (web `.lk-status--accent::before`).
    var dot: Color {
        self == .accent ? .studioAccentLine : ink
    }

    var fill: Color {
        switch self {
        case .success: return .studioSuccessSoft
        case .warning: return .studioWarningSoft
        case .error: return .studioErrorSoft
        case .info: return .studioInfoSoft
        case .neutral: return .studioSurface3
        case .accent: return .studioAccentSoft
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .neutral: return "circle.fill"
        case .accent: return "sparkles"
        }
    }
}

public struct StudioStatusPill: View {
    private let title: String
    private let tone: StudioTone

    public init(_ title: String, tone: StudioTone = .neutral) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.dot).frame(width: 5, height: 5)
            Text(title).studioText(.meta)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .foregroundStyle(tone.ink)
        .background(tone.fill, in: Capsule())
    }
}

// MARK: - Banner

/// An inline banner. Never colour-only: the icon and the bold lead phrase
/// carry the meaning independently of hue.
public struct StudioBanner: View {
    private let lead: String
    private let message: String
    private let tone: StudioTone

    public init(lead: String, message: String, tone: StudioTone = .info) {
        self.lead = lead
        self.message = message
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .top, spacing: StudioSpace.s3) {
            Image(systemName: tone.symbol)
                .font(.system(size: 17))
            (
                Text(lead).fontWeight(.bold)
                + Text(" ")
                + Text(message)
            )
            .studioText(.ui)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(StudioSpace.s4)
        .foregroundStyle(tone.ink)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                .strokeBorder(tone.ink.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Badge

public struct StudioBadge: View {
    private let text: String
    private let isNeutral: Bool

    public init(_ text: String, neutral: Bool = false) {
        self.text = text
        self.isNeutral = neutral
    }

    public var body: some View {
        Text(text)
            .studioText(.meta)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 18)
            .foregroundStyle(isNeutral ? Color.studioText2 : Color.studioAccentInk)
            .background(isNeutral ? Color.studioSurface3 : Color.studioAccent, in: Capsule())
    }
}

// MARK: - Empty state

/// `compact` drops the dashed frame and tightens the padding, for an
/// empty state whose container already draws the frame (ADR-0028) —
/// the `.lk-empty--compact` variant. The default is free-standing.
public struct StudioEmptyState<Actions: View>: View {
    private let systemImage: String
    private let title: String
    private let accent: String
    private let message: String
    private let compact: Bool
    private let actions: Actions

    public init(
        systemImage: String,
        title: String,
        accent: String = "",
        message: String,
        compact: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.accent = accent
        self.message = message
        self.compact = compact
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: StudioSpace.s4) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(Color.studioAccentLine)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                        .fill(Color.studioAccentSoft)
                )

            VStack(spacing: StudioSpace.s2) {
                if accent.isEmpty {
                    Text(title).studioText(.titleSm)
                } else {
                    StudioTwoToneTitle(title, accent: accent, style: .titleSm)
                }
                Text(message)
                    .studioText(.body)
                    .foregroundStyle(Color.studioText2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)

            HStack(spacing: StudioSpace.s3) { actions }
                .padding(.top, StudioSpace.s2)
        }
        .padding(.vertical, compact ? StudioSpace.s5 : StudioSpace.s12)
        .padding(.horizontal, compact ? StudioSpace.s5 : StudioSpace.s6)
        .frame(maxWidth: .infinity)
        // Compact keeps the layout and loses only the paint — the web
        // rule swaps background to none and border-color to transparent.
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .fill(compact ? Color.clear : Color.studioSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                .strokeBorder(
                    compact ? Color.clear : Color.studioBorderStrong,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
    }
}

// MARK: - Text field

public struct StudioTextField: View {
    private let label: String
    private let placeholder: String
    private let help: String?
    private let errorMessage: String?
    @Binding private var text: String

    @FocusState private var isFocused: Bool

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        help: String? = nil,
        errorMessage: String? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.help = help
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .studioText(.uiSm)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioText)

            TextField(placeholder, text: $text)
                // Plain, so macOS does not draw its own bezel inside ours.
                .textFieldStyle(.plain)
                .studioText(.ui)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                        .fill(isFocused ? Color.studioSurface : Color.studioSurface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused || hasError ? 1 : 0.5)
                )
                // The 3px accent glow ring — the one coloured glow in the system.
                .overlay(
                    RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                        .strokeBorder(Color.studioAccentGlow, lineWidth: isFocused && !hasError ? 3 : 0)
                        .padding(-2)
                )
                .animation(StudioAnimation.base, value: isFocused)

            if let message = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11))
                    Text(message)
                }
                .studioText(.uiSm)
                .foregroundStyle(Color.studioError)
            } else if let help {
                Text(help)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var hasError: Bool { errorMessage != nil }

    private var borderColor: Color {
        if hasError { return .studioError }
        return isFocused ? .studioAccentLine : .studioBorder
    }
}
