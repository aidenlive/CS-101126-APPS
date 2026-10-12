import SwiftUI

/*
 StudioKit doesn't build for watchOS: its Package.swift declares iOS and
 macOS only, its colours resolve through UIKit trait collections the watch
 doesn't have, and its four font families would cost the watch app's
 bundle size for a handful of labels. So the watch uses this palette,
 copied from the DARK values of the Studio tokens (the watch is always
 dark) in platform/studio/packages/swift/Sources/StudioKit/Generated/
 StudioTokens.swift, and the system font, whose text styles scale with
 the watch's own text size setting.

 Keep these in step with the token file when the tokens change.
 */
enum WatchPalette {
    /// `studioAccent`, dark: the one accent fill.
    static let accent = Color(.sRGB, red: 0.4843, green: 0.9494, blue: 0.285)
    /// `studioAccentLine`, dark: accent ink for glyphs and the tint.
    static let accentLine = Color(.sRGB, red: 0.2593, green: 0.7652, blue: 0.2167)
    /// `studioAccentInk`: text on `accent`.
    static let accentInk = Color(.sRGB, red: 0, green: 0.0574, blue: 0)
    /// `studioText2`, dark: secondary ink.
    static let text2 = Color(.sRGB, red: 0.6389, green: 0.6447, blue: 0.6604)
    /// `studioText3`, dark: metadata.
    static let text3 = Color(.sRGB, red: 0.5306, green: 0.5371, blue: 0.5548)
    /// `studioError`, dark.
    static let error = Color(.sRGB, red: 1, green: 0.2937, blue: 0.3396)
    /// `StudioPalette.neutral0`: the QR screen's quiet zone, white at full
    /// brightness so a scanner reads the code off the watch.
    static let qrGround = Color(.sRGB, red: 1, green: 1, blue: 1)
    /// `StudioPalette.neutral950`: ink on the white QR screen.
    static let qrInk = Color(.sRGB, red: 0.019, green: 0.0221, blue: 0.0328)
}

/// `StudioSpace` steps the watch uses (4 pt base unit).
enum WatchSpace {
    /// Between a title and its metadata line.
    static let hairline: CGFloat = 2
    /// `StudioSpace.s1`.
    static let s1: CGFloat = 4
    /// `StudioSpace.s2`.
    static let s2: CGFloat = 8
}
