import SwiftUI

/*
 Accent re-pointing.

 The web has had this since v1.0: set `data-primary="violet"` on any root
 and every accent-derived value follows, in both themes. This is the same
 capability, generated from the SAME `primaryFamilies` block the CSS reads
 (see `StudioAccentFamily` in Generated/StudioTokens.swift), so the two
 platforms cannot disagree about what "violet" means.

     ContentView()
         .studioAccent(.violet)

 `Color.studioAccent` and its siblings are static tokens and always mean
 the default family (lime). Paint with `StudioAccentStyle.accent` (and
 `.ink`, `.soft`, `.line`, `.active`, `.glow`) wherever a re-point should
 be honoured; those resolve the family from the environment at draw time.
 No component takes an accent parameter: the moment one does, half the
 system follows the environment and the other half follows a prop.
 */

private struct StudioAccentFamilyKey: EnvironmentKey {
    static let defaultValue: StudioAccentFamily = .default
}

public extension EnvironmentValues {
    /// The accent family in force. Read it only if you need the ramp
    /// directly — for painting, prefer `StudioAccentStyle`.
    var studioAccentFamily: StudioAccentFamily {
        get { self[StudioAccentFamilyKey.self] }
        set { self[StudioAccentFamilyKey.self] = newValue }
    }
}

public extension View {
    /// Re-points the accent for this subtree — the counterpart of
    /// `data-primary` on the web. Also sets the subtree's `tint` to the
    /// family's line value (theme-aware), so native controls follow.
    func studioAccent(_ family: StudioAccentFamily) -> some View {
        // Tint first, environment outermost: the tint style resolves in
        // the children, where the family is already in the environment.
        tint(StudioAccentStyle.line)
            .environment(\.studioAccentFamily, family)
    }
}

// MARK: - Resolving style

/// A `ShapeStyle` that resolves one accent role through the environment:
/// the family set by `.studioAccent(_:)` and the current colour scheme.
///
///     .foregroundStyle(StudioAccentStyle.accent)
///     .background(StudioAccentStyle.soft, in: Capsule())
public struct StudioAccentStyle: ShapeStyle, Sendable {
    public enum Role: Sendable {
        case accent, ink, soft, line, active, glow
    }

    private let role: Role

    public init(_ role: Role) {
        self.role = role
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        let ramp = environment.studioAccentFamily
            .ramp(dark: environment.colorScheme == .dark)
        switch role {
        case .accent: return ramp.accent
        case .ink:    return ramp.ink
        case .soft:   return ramp.soft
        case .line:   return ramp.line
        case .active: return ramp.active
        case .glow:   return ramp.glow
        }
    }
}

/*
 The six roles as ready-made styles. They live on the concrete type as
 `static let` (legal under strict concurrency) rather than as computed
 statics in a `ShapeStyle` extension.
 */
public extension StudioAccentStyle {
    /// The accent fill, resolved through any `.studioAccent(_:)` above it.
    static let accent = StudioAccentStyle(.accent)
    /// Ink that sits legibly on the accent.
    static let ink = StudioAccentStyle(.ink)
    /// The 16–18% wash used for selection states.
    static let soft = StudioAccentStyle(.soft)
    /// The hairline and focus-ring value (3:1 against surfaces).
    static let line = StudioAccentStyle(.line)
    /// The pressed value.
    static let active = StudioAccentStyle(.active)
    /// The glow, for tinted glass and accent shadows.
    static let glow = StudioAccentStyle(.glow)
}
