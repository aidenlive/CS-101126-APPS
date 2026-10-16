//    STUDIO — StudioTokens.swift
// GENERATED FILE — DO NOT EDIT.

// Source:    tokens/studio.tokens.json
// Generator: tokens/build.mjs
// System:    Studio v1.2.0
// Spec:      docs/DESIGN.md

// Edit the JSON and run `npm run build:tokens`.
// 

import SwiftUI
#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

// MARK: - Colour

/// sRGB helper — every Studio colour is authored in OKLCH and converted at build time.
private func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

#if canImport(UIKit)
/// Resolves light/dark automatically from the trait environment, so a single
/// token name works in both themes exactly as the CSS custom properties do.
private func dynamicColor(
    light: (Double, Double, Double, Double),
    dark: (Double, Double, Double, Double)
) -> Color {
    Color(UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
    })
}
#elseif canImport(AppKit)
/// AppKit twin of the UIKit helper: resolves against the effective appearance,
/// so native macOS follows the system (and `.preferredColorScheme`) into dark.
/// High-contrast appearances resolve to their light/dark base.
private func dynamicColor(
    light: (Double, Double, Double, Double),
    dark: (Double, Double, Double, Double)
) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
        ])
        let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let c = isDark ? dark : light
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
    })
}
#else
private func dynamicColor(
    light: (Double, Double, Double, Double),
    dark: (Double, Double, Double, Double)
) -> Color {
    srgb(light.0, light.1, light.2, light.3)
}
#endif

/// The themed semantic layer. **Views consume these, never the palette.**
public extension Color {
    // MARK: Semantic
    // surface
    /// The page.
    static let studioBg = dynamicColor(light: (0.9706, 0.9737, 0.9822, 1), dark: (0.019, 0.0221, 0.0328, 1))
    /// One step deeper — the sidebar and the canvas behind floating chrome.
    static let studioBgEdge = dynamicColor(light: (0.9304, 0.9345, 0.9457, 1), dark: (0.0055, 0.0065, 0.0102, 1))
    /// Resting card / panel fill.
    static let studioSurface = dynamicColor(light: (1, 1, 1, 1), dark: (0.0465, 0.0515, 0.0658, 1))
    /// Hover fill — one step forward.
    static let studioSurface2 = dynamicColor(light: (0.946, 0.9501, 0.9614, 1), dark: (0.0798, 0.0859, 0.1029, 1))
    /// Pressed fill / media placeholder.
    static let studioSurface3 = dynamicColor(light: (0.9034, 0.9085, 0.9225, 1), dark: (0.1149, 0.122, 0.1418, 1))
    // border
    /// Hairline definition — always 0.5px.
    static let studioBorder = dynamicColor(light: (0.8381, 0.8442, 0.8607, 1), dark: (0.1428, 0.1501, 0.1705, 1))
    /// The hover step. Step to this instead of thickening.
    static let studioBorderStrong = dynamicColor(light: (0.7105, 0.7183, 0.7396, 1), dark: (0.2303, 0.239, 0.2631, 1))
    // text
    /// Primary ink. 16.9:1 on surface.
    static let studioText = dynamicColor(light: (0.0287, 0.0349, 0.0555, 1), dark: (0.9564, 0.9606, 0.9719, 1))
    /// Secondary ink. 7.4:1 on surface.
    static let studioText2 = dynamicColor(light: (0.2731, 0.2805, 0.3008, 1), dark: (0.6389, 0.6447, 0.6604, 1))
    /// Muted — kickers, metadata, placeholders, the serif accent word. At least 4.5:1 on every surface in both themes (scripts/check-contrast.mjs).
    static let studioText3 = dynamicColor(light: (0.3935, 0.3996, 0.4164, 1), dark: (0.5306, 0.5371, 0.5548, 1))
    /// Faint — disabled ink and decorative glyphs only. Under 4.5:1 by design, so nothing a reader must read: placeholders use --text-3.
    static let studioText4 = dynamicColor(light: (0.6389, 0.6447, 0.6604, 1), dark: (0.274, 0.2805, 0.2985, 1))
    // accent
    /// The accent fill.
    static let studioAccent = dynamicColor(light: (0.3995, 0.8391, 0.1947, 1), dark: (0.4843, 0.9494, 0.285, 1))
    /// Text and icons ON accent. Always this, never white.
    static let studioAccentInk = dynamicColor(light: (0, 0.0545, 0.0003, 1), dark: (0, 0.0574, 0, 1))
    /// Soft fill for selected rows, icon tiles, pressed toolbar buttons.
    static let studioAccentSoft = dynamicColor(light: (0.3995, 0.8391, 0.1947, 0.16), dark: (0.4843, 0.9494, 0.285, 0.18))
    /// Accent borders, focus outlines, hover deepening. At least 3:1 against every surface (WCAG 1.4.11), and the primary button's hover fill under --accent-ink.
    static let studioAccentLine = dynamicColor(light: (0.008, 0.584, 0, 1), dark: (0.2593, 0.7652, 0.2167, 1))
    /// The 3px input focus ring. The only place a coloured glow is allowed.
    static let studioAccentGlow = dynamicColor(light: (0.3995, 0.8391, 0.1947, 0.5), dark: (0.4843, 0.9494, 0.285, 0.5))
    /// Pressed primary.
    static let studioAccentActive = dynamicColor(light: (0.1654, 0.5522, 0, 1), dark: (0.3995, 0.8391, 0.1947, 1))
    // status
    static let studioError = dynamicColor(light: (0.7732, 0, 0.1684, 1), dark: (1, 0.2937, 0.3396, 1))
    static let studioSuccess = dynamicColor(light: (0.0751, 0.4661, 0.2198, 1), dark: (0.2341, 0.7887, 0.4153, 1))
    static let studioWarning = dynamicColor(light: (0.5923, 0.3456, 0, 1), dark: (0.9683, 0.7142, 0.3292, 1))
    static let studioInfo = dynamicColor(light: (0.0749, 0.3247, 0.8121, 1), dark: (0.2953, 0.5225, 0.9601, 1))
    /// 12% fill (16% dark) for chips and inline banners.
    static let studioErrorSoft = dynamicColor(light: (0.7732, 0, 0.1684, 0.12), dark: (1, 0.2937, 0.3396, 0.16))
    static let studioSuccessSoft = dynamicColor(light: (0.0751, 0.4661, 0.2198, 0.12), dark: (0.2341, 0.7887, 0.4153, 0.16))
    static let studioWarningSoft = dynamicColor(light: (0.5923, 0.3456, 0, 0.12), dark: (0.9683, 0.7142, 0.3292, 0.16))
    static let studioInfoSoft = dynamicColor(light: (0.0749, 0.3247, 0.8121, 0.12), dark: (0.2953, 0.5225, 0.9601, 0.16))
    // code
    /// Keywords and tags.
    static let studioCodeKey = dynamicColor(light: (0.2097, 0.2402, 0.7876, 1), dark: (0.4966, 0.587, 0.9625, 1))
    /// Strings.
    static let studioCodeStr = dynamicColor(light: (0, 0.4499, 0.2771, 1), dark: (0.2595, 0.726, 0.5387, 1))
    /// Numbers, units, hex colours.
    static let studioCodeNum = dynamicColor(light: (0.4829, 0.2885, 0, 1), dark: (0.9683, 0.7142, 0.3292, 1))
    /// Attributes, properties, object keys, custom properties.
    static let studioCodeAttr = dynamicColor(light: (0, 0.4233, 0.6289, 1), dark: (0.342, 0.7106, 0.9251, 1))
    /// Functions and selectors.
    static let studioCodeFn = dynamicColor(light: (0.4994, 0.1235, 0.769, 1), dark: (0.6594, 0.3804, 0.9229, 1))
    /// Comments and punctuation. Follows --text-3, which flips on its own, so this one value serves both themes.
    static let studioCodeMut = dynamicColor(light: (0.3935, 0.3996, 0.4164, 1), dark: (0.5306, 0.5371, 0.5548, 1))
    // material
    static let studioGlassBg = dynamicColor(light: (1, 1, 1, 0.72), dark: (0.0465, 0.0515, 0.0658, 0.72))
    static let studioGlassBorder = dynamicColor(light: (1, 1, 1, 0.65), dark: (1, 1, 1, 0.08))
    /// Modal scrim, paired with a 2px backdrop blur.
    static let studioScrim = dynamicColor(light: (0.0297, 0.0351, 0.0522, 0.34), dark: (0.0006, 0.0008, 0.0016, 0.6))
    // canvas
    /// The recessed work plane behind an artboard.
    static let studioCanvasBg = dynamicColor(light: (0.9174, 0.9215, 0.9327, 1), dark: (0.0109, 0.0128, 0.0193, 1))
    /// Minor grid. Orientation only — must never out-contrast content.
    static let studioCanvasGrid = dynamicColor(light: (0.637, 0.6446, 0.6656, 0.28), dark: (0.6109, 0.6204, 0.6464, 0.16))
    /// Major grid, every 8th minor line. Carries the ruler rhythm.
    static let studioCanvasGridMajor = dynamicColor(light: (0.5396, 0.5488, 0.5742, 0.34), dark: (0.6575, 0.6689, 0.7005, 0.22))
    /// Artboard fill. Tracks --surface but stays separate: an artboard is content, not chrome.
    static let studioCanvasArtboard = dynamicColor(light: (1, 1, 1, 1), dark: (0.0633, 0.0685, 0.0832, 1))
    /// Selection outline on canvas. Follows --accent-line, so it keeps the 3:1 non-text contrast fix.
    static let studioCanvasSelection = dynamicColor(light: (0.008, 0.584, 0, 1), dark: (0.2593, 0.7652, 0.2167, 1))
    /// Marquee / hover wash.
    static let studioCanvasSelectionSoft = dynamicColor(light: (0.3995, 0.8391, 0.1947, 0.14), dark: (0.4843, 0.9494, 0.285, 0.16))
    // identity
    /// Avatar fill when there is no image.
    static let studioIdentityBg = dynamicColor(light: (0.9034, 0.9085, 0.9225, 1), dark: (0.1149, 0.122, 0.1418, 1))
    /// Initials on --identity-bg.
    static let studioIdentityInk = dynamicColor(light: (0.1508, 0.1596, 0.1842, 1), dark: (0.8894, 0.8955, 0.9123, 1))
    /// The ring separating stacked avatars from whatever is behind them.
    static let studioIdentityRing = dynamicColor(light: (1, 1, 1, 1), dark: (0.0465, 0.0515, 0.0658, 1))
}

// MARK: - Data visualisation

/// The chart palette, from `dataviz` in the token file (`--viz-*`).
///
/// Charts speak the same language as the UI: flat fills, hairline
/// structure, label-face figures. Lime is NOT in the rotation — the
/// accent highlights exactly one series (the current, selected or "you"
/// series). Six is the ceiling; beyond that, group the remainder into
/// `studioVizOther`. Status colours never encode data.
///
/// The categorical steps are theme-independent palette steps (identical
/// light and dark values, as the CSS has them); grid and highlight follow
/// `--border` and `--accent`, so they flip with the theme.
public extension Color {
    // MARK: Dataviz
    /// Categorical series 1 of 6 (`--viz-1`, blue-500).
    static let studioViz1 = dynamicColor(light: (0.1385, 0.3996, 0.915, 1), dark: (0.1385, 0.3996, 0.915, 1))
    /// Categorical series 2 of 6 (`--viz-2`, violet-400).
    static let studioViz2 = dynamicColor(light: (0.4952, 0.4105, 0.9931, 1), dark: (0.4952, 0.4105, 0.9931, 1))
    /// Categorical series 3 of 6 (`--viz-3`, teal-500).
    static let studioViz3 = dynamicColor(light: (0, 0.7215, 0.6508, 1), dark: (0, 0.7215, 0.6508, 1))
    /// Categorical series 4 of 6 (`--viz-4`, amber-500).
    static let studioViz4 = dynamicColor(light: (0.9491, 0.6513, 0.095, 1), dark: (0.9491, 0.6513, 0.095, 1))
    /// Categorical series 5 of 6 (`--viz-5`, pink-500).
    static let studioViz5 = dynamicColor(light: (0.8857, 0.184, 0.6008, 1), dark: (0.8857, 0.184, 0.6008, 1))
    /// Categorical series 6 of 6 (`--viz-6`, cyan-600).
    static let studioViz6 = dynamicColor(light: (0, 0.5896, 0.7027, 1), dark: (0, 0.5896, 0.7027, 1))
    /// The one highlighted series (`--viz-highlight`, follows --accent).
    static let studioVizHighlight = dynamicColor(light: (0.3995, 0.8391, 0.1947, 1), dark: (0.4843, 0.9494, 0.285, 1))
    /// The grouped remainder (`--viz-other`, neutral-400).
    static let studioVizOther = dynamicColor(light: (0.7105, 0.7183, 0.7396, 1), dark: (0.7105, 0.7183, 0.7396, 1))
    /// Gridlines and axes — neutral hairlines (`--viz-grid`, follows --border).
    static let studioVizGrid = dynamicColor(light: (0.8381, 0.8442, 0.8607, 1), dark: (0.1428, 0.1501, 0.1705, 1))

    /// The fixed categorical rotation, in order — `--viz-1…6`. Feed it to
    /// `chartForegroundStyleScale(domain:range:)`; never cycle past six.
    static let studioVizCategorical: [Color] = [
        studioViz1, studioViz2, studioViz3, studioViz4, studioViz5, studioViz6,
    ]
}

/// The raw palette. Theme-independent primitives — reference these only when
/// building a new semantic token or a data-visualisation scale.
public extension Color {
    enum StudioPalette {
        // neutral
        public static let neutral0 = srgb(1, 1, 1)
        public static let neutral50 = srgb(0.9706, 0.9737, 0.9822)
        public static let neutral100 = srgb(0.946, 0.9501, 0.9614)
        public static let neutral200 = srgb(0.9034, 0.9085, 0.9225)
        public static let neutral300 = srgb(0.8381, 0.8442, 0.8607)
        public static let neutral400 = srgb(0.7105, 0.7183, 0.7396)
        public static let neutral500 = srgb(0.5424, 0.5489, 0.5667)
        public static let neutral600 = srgb(0.4038, 0.4108, 0.4301)
        public static let neutral700 = srgb(0.2731, 0.2805, 0.3008)
        public static let neutral800 = srgb(0.1523, 0.1597, 0.1802)
        public static let neutral900 = srgb(0.0784, 0.0858, 0.1065)
        public static let neutral950 = srgb(0.019, 0.0221, 0.0328)
        // blue
        public static let blue50 = srgb(0.9196, 0.9707, 1)
        public static let blue100 = srgb(0.7755, 0.8615, 1)
        public static let blue200 = srgb(0.6192, 0.7523, 0.993)
        public static let blue300 = srgb(0.4567, 0.6401, 0.9806)
        public static let blue400 = srgb(0.2953, 0.5225, 0.9601)
        public static let blue500 = srgb(0.1385, 0.3996, 0.915)
        public static let blue600 = srgb(0.0749, 0.3247, 0.8121)
        public static let blue700 = srgb(0.0293, 0.2577, 0.6929)
        public static let blue800 = srgb(0.0232, 0.2025, 0.5517)
        public static let blue900 = srgb(0.0218, 0.1515, 0.4113)
        public static let blue950 = srgb(0.019, 0.1029, 0.277)
        // sky
        public static let sky50 = srgb(0.9163, 0.9784, 1)
        public static let sky100 = srgb(0.7996, 0.9093, 0.9822)
        public static let sky200 = srgb(0.6647, 0.8432, 0.9593)
        public static let sky300 = srgb(0.5131, 0.7776, 0.9434)
        public static let sky400 = srgb(0.342, 0.7106, 0.9251)
        public static let sky500 = srgb(0.1321, 0.6407, 0.8905)
        public static let sky600 = srgb(0, 0.5304, 0.7626)
        public static let sky700 = srgb(0, 0.4233, 0.6289)
        public static let sky800 = srgb(0, 0.32, 0.4859)
        public static let sky900 = srgb(0, 0.2218, 0.3434)
        public static let sky950 = srgb(0, 0.1303, 0.212)
        // cyan
        public static let cyan50 = srgb(0.909, 0.9835, 1)
        public static let cyan100 = srgb(0.7972, 0.9253, 0.9583)
        public static let cyan200 = srgb(0.6583, 0.8725, 0.9266)
        public static let cyan300 = srgb(0.4977, 0.8207, 0.899)
        public static let cyan400 = srgb(0.2995, 0.7676, 0.8704)
        public static let cyan500 = srgb(0, 0.7099, 0.8305)
        public static let cyan600 = srgb(0, 0.5896, 0.7027)
        public static let cyan700 = srgb(0, 0.471, 0.5707)
        public static let cyan800 = srgb(0, 0.3548, 0.4349)
        public static let cyan900 = srgb(0, 0.2439, 0.3026)
        public static let cyan950 = srgb(0, 0.141, 0.1807)
        // teal
        public static let teal50 = srgb(0.9108, 0.9873, 0.9725)
        public static let teal100 = srgb(0.7976, 0.9291, 0.9046)
        public static let teal200 = srgb(0.6579, 0.8779, 0.8396)
        public static let teal300 = srgb(0.4964, 0.8284, 0.7762)
        public static let teal400 = srgb(0.2964, 0.7779, 0.7139)
        public static let teal500 = srgb(0, 0.7215, 0.6508)
        public static let teal600 = srgb(0, 0.6026, 0.5384)
        public static let teal700 = srgb(0, 0.4841, 0.4288)
        public static let teal800 = srgb(0, 0.3666, 0.3225)
        public static let teal900 = srgb(0, 0.2537, 0.2213)
        public static let teal950 = srgb(0, 0.1491, 0.1274)
        // emerald
        public static let emerald50 = srgb(0.9144, 0.9892, 0.9496)
        public static let emerald100 = srgb(0.7867, 0.9174, 0.8497)
        public static let emerald200 = srgb(0.638, 0.8524, 0.746)
        public static let emerald300 = srgb(0.4684, 0.7898, 0.6414)
        public static let emerald400 = srgb(0.2595, 0.726, 0.5387)
        public static let emerald500 = srgb(0, 0.6562, 0.4439)
        public static let emerald600 = srgb(0, 0.5531, 0.3566)
        public static let emerald700 = srgb(0, 0.4499, 0.2771)
        public static let emerald800 = srgb(0, 0.3461, 0.2073)
        public static let emerald900 = srgb(0, 0.2459, 0.1431)
        public static let emerald950 = srgb(0, 0.152, 0.0829)
        // green
        public static let green50 = srgb(0.9226, 0.9891, 0.9286)
        public static let green100 = srgb(0.8029, 0.9203, 0.8147)
        public static let green200 = srgb(0.6688, 0.8572, 0.6908)
        public static let green300 = srgb(0.5204, 0.7965, 0.5601)
        public static let green400 = srgb(0.3565, 0.7345, 0.4278)
        public static let green500 = srgb(0.1715, 0.6664, 0.3057)
        public static let green600 = srgb(0.0149, 0.5604, 0.2201)
        public static let green700 = srgb(0, 0.4549, 0.1478)
        public static let green800 = srgb(0, 0.3488, 0.1015)
        public static let green900 = srgb(0, 0.2468, 0.064)
        public static let green950 = srgb(0, 0.151, 0.0311)
        // lime
        public static let lime50 = srgb(0.9243, 0.9918, 0.9025)
        public static let lime100 = srgb(0.8398, 0.9584, 0.801)
        public static let lime200 = srgb(0.7414, 0.9301, 0.6786)
        public static let lime300 = srgb(0.6301, 0.9038, 0.5354)
        public static let lime400 = srgb(0.5112, 0.875, 0.3737)
        public static let lime500 = srgb(0.3995, 0.8391, 0.1947)
        public static let lime600 = srgb(0.2746, 0.6947, 0)
        public static let lime700 = srgb(0.1654, 0.5522, 0)
        public static let lime800 = srgb(0.0939, 0.4111, 0)
        public static let lime900 = srgb(0.0368, 0.2767, 0)
        public static let lime950 = srgb(0.0044, 0.1523, 0)
        // yellow
        public static let yellow50 = srgb(0.9831, 0.9712, 0.891)
        public static let yellow100 = srgb(0.9603, 0.9382, 0.7951)
        public static let yellow200 = srgb(0.9429, 0.9053, 0.6722)
        public static let yellow300 = srgb(0.9292, 0.8712, 0.5232)
        public static let yellow400 = srgb(0.916, 0.8355, 0.3445)
        public static let yellow500 = srgb(0.8973, 0.799, 0.108)
        public static let yellow600 = srgb(0.74, 0.6464, 0)
        public static let yellow700 = srgb(0.5851, 0.5005, 0)
        public static let yellow800 = srgb(0.4312, 0.3629, 0)
        public static let yellow900 = srgb(0.2849, 0.2343, 0)
        public static let yellow950 = srgb(0.15, 0.1164, 0)
        // amber
        public static let amber50 = srgb(1, 0.9599, 0.8942)
        public static let amber100 = srgb(0.9886, 0.9031, 0.7894)
        public static let amber200 = srgb(0.9788, 0.843, 0.6594)
        public static let amber300 = srgb(0.9747, 0.7796, 0.5064)
        public static let amber400 = srgb(0.9683, 0.7142, 0.3292)
        public static let amber500 = srgb(0.9491, 0.6513, 0.095)
        public static let amber600 = srgb(0.7978, 0.5202, 0)
        public static let amber700 = srgb(0.6429, 0.3983, 0)
        public static let amber800 = srgb(0.4829, 0.2885, 0)
        public static let amber900 = srgb(0.3299, 0.1864, 0)
        public static let amber950 = srgb(0.1874, 0.093, 0)
        // orange
        public static let orange50 = srgb(1, 0.9454, 0.9041)
        public static let orange100 = srgb(1, 0.8511, 0.7793)
        public static let orange200 = srgb(1, 0.748, 0.6333)
        public static let orange300 = srgb(1, 0.6375, 0.4722)
        public static let orange400 = srgb(0.9877, 0.5206, 0.2939)
        public static let orange500 = srgb(0.952, 0.4071, 0.0599)
        public static let orange600 = srgb(0.816, 0.3056, 0)
        public static let orange700 = srgb(0.6732, 0.2171, 0)
        public static let orange800 = srgb(0.5205, 0.1515, 0)
        public static let orange900 = srgb(0.3691, 0.0986, 0)
        public static let orange950 = srgb(0.2291, 0.0475, 0)
        // red
        public static let red50 = srgb(1, 0.9321, 0.924)
        public static let red100 = srgb(1, 0.803, 0.7911)
        public static let red200 = srgb(1, 0.6594, 0.6462)
        public static let red300 = srgb(0.9821, 0.5017, 0.4967)
        public static let red400 = srgb(0.9495, 0.3209, 0.3474)
        public static let red500 = srgb(0.8882, 0.0456, 0.2078)
        public static let red600 = srgb(0.7759, 0, 0.1394)
        public static let red700 = srgb(0.6525, 0, 0.0876)
        public static let red800 = srgb(0.5167, 0, 0.0612)
        public static let red900 = srgb(0.381, 0, 0.0442)
        public static let red950 = srgb(0.2543, 0, 0.0265)
        // pink
        public static let pink50 = srgb(1, 0.9302, 0.9814)
        public static let pink100 = srgb(1, 0.8104, 0.8991)
        public static let pink200 = srgb(0.9894, 0.6761, 0.8226)
        public static let pink300 = srgb(0.9696, 0.5297, 0.7491)
        public static let pink400 = srgb(0.9399, 0.3679, 0.6764)
        public static let pink500 = srgb(0.8857, 0.184, 0.6008)
        public static let pink600 = srgb(0.7661, 0.0533, 0.5065)
        public static let pink700 = srgb(0.6375, 0, 0.4123)
        public static let pink800 = srgb(0.4991, 0, 0.3182)
        public static let pink900 = srgb(0.3621, 0, 0.2274)
        public static let pink950 = srgb(0.2345, 0.0019, 0.1424)
        // purple
        public static let purple50 = srgb(0.9904, 0.9447, 1)
        public static let purple100 = srgb(0.8973, 0.8166, 1)
        public static let purple200 = srgb(0.8133, 0.6809, 0.9707)
        public static let purple300 = srgb(0.7354, 0.5366, 0.9496)
        public static let purple400 = srgb(0.6594, 0.3804, 0.9229)
        public static let purple500 = srgb(0.5788, 0.2057, 0.8706)
        public static let purple600 = srgb(0.4994, 0.1235, 0.769)
        public static let purple700 = srgb(0.4173, 0.0545, 0.6552)
        public static let purple800 = srgb(0.3304, 0.0418, 0.5233)
        public static let purple900 = srgb(0.2442, 0.0463, 0.3884)
        public static let purple950 = srgb(0.1632, 0.0378, 0.2626)
        // violet
        public static let violet50 = srgb(0.9541, 0.9557, 1)
        public static let violet100 = srgb(0.8308, 0.8303, 1)
        public static let violet200 = srgb(0.7099, 0.6998, 1)
        public static let violet300 = srgb(0.5963, 0.5612, 1)
        public static let violet400 = srgb(0.4952, 0.4105, 0.9931)
        public static let violet500 = srgb(0.4082, 0.2383, 0.9489)
        public static let violet600 = srgb(0.3491, 0.1614, 0.8468)
        public static let violet700 = srgb(0.2896, 0.1017, 0.7274)
        public static let violet800 = srgb(0.2281, 0.0837, 0.5834)
        public static let violet900 = srgb(0.1681, 0.0746, 0.4368)
        public static let violet950 = srgb(0.1116, 0.0592, 0.2984)
        // indigo
        public static let indigo50 = srgb(0.9341, 0.9649, 1)
        public static let indigo100 = srgb(0.7899, 0.8411, 1)
        public static let indigo200 = srgb(0.6423, 0.7162, 0.9818)
        public static let indigo300 = srgb(0.4966, 0.587, 0.9625)
        public static let indigo400 = srgb(0.3631, 0.4501, 0.9367)
        public static let indigo500 = srgb(0.2551, 0.3044, 0.8815)
        public static let indigo600 = srgb(0.2097, 0.2402, 0.7876)
        public static let indigo700 = srgb(0.1686, 0.1857, 0.6794)
        public static let indigo800 = srgb(0.1317, 0.1504, 0.547)
        public static let indigo900 = srgb(0.0973, 0.1197, 0.4128)
        public static let indigo950 = srgb(0.0657, 0.0889, 0.284)
    }
}

// MARK: - Metrics

/// Corner radii. Radii scale with element size; nothing is right-angled
/// except full-bleed imagery.
public enum StudioRadius {
    /// Checkboxes, code chips.
    public static let xs: CGFloat = 6
    /// Tooltips, compact controls.
    public static let sm: CGFloat = 10
    /// Form fields, menu items, inline banners.
    public static let md: CGFloat = 14
    /// Cards, modals, media frames.
    public static let lg: CGFloat = 20
    /// Heroes, the account card.
    public static let xl: CGFloat = 28
    /// Buttons, chips, inputs, toasts, every piece of chrome.
    public static let pill: CGFloat = 999
}

/// Spacing scale — 4px base unit.
public enum StudioSpace {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 20
    public static let s6: CGFloat = 24
    public static let s8: CGFloat = 32
    public static let s10: CGFloat = 40
    public static let s12: CGFloat = 48
    public static let s16: CGFloat = 64
}

/// Layout metrics.
public enum StudioLayout {
    /// Sidebar, expanded.
    public static let sidebarFull: CGFloat = 256
    /// Sidebar, collapsed icon rail.
    public static let sidebarRail: CGFloat = 76
    /// Header row.
    public static let headerHeight: CGFloat = 72
    /// Every piece of floating chrome sits this far from the viewport edge, plus safe-area.
    public static let floatInset: CGFloat = 14
    /// Every floating chrome pill is this tall — topbar pills, avatar, dock.
    public static let pillHeight: CGFloat = 52
    /// Controls nested INSIDE a pill: icon buttons, links, the dock search field.
    public static let controlHeight: CGFloat = 36
    /// The dock primary action disc. Smaller than a pill so it reads as a child of the dock, not a peer.
    public static let dockAction: CGFloat = 44
    /// Minimum interactive target. Never ship smaller.
    public static let tapTarget: CGFloat = 44

    /// Size-class thresholds, matching the CSS breakpoints exactly.
    public static let bpDesktop: CGFloat = 1100
    public static let bpTablet: CGFloat = 720
}

/// Motion durations, in seconds. Honour `accessibilityReduceMotion`:
/// the CSS layer collapses these to 0.01s, so the Swift layer must too.
public enum StudioDuration {
    /// Hovers, dropdown and toast reveals, tab cross-fades.
    public static let fast: Double = 0.18
    /// Toggles, pill slides, springy state changes.
    public static let med: Double = 0.28
    /// Page pushes, large-surface reveals.
    public static let slow: Double = 0.42
}

/// The three easings, each with one job. SwiftUI has no cubic-Bézier
/// initialiser, so these are the closest native equivalents of the CSS curves.
public enum StudioAnimation {
    /// `--ease` cubic-bezier(0.4, 0, 0.2, 1) — general transitions and hovers.
    public static let base = Animation.easeInOut(duration: StudioDuration.fast)
    /// `--ease-out` cubic-bezier(0.16, 1, 0.3, 1) — decelerating reveals, page pushes.
    public static let out = Animation.easeOut(duration: StudioDuration.slow)
    /// `--ease-spring` cubic-bezier(0.34, 1.56, 0.64, 1) — anything physical.
    public static let spring = Animation.spring(response: StudioDuration.med, dampingFraction: 0.66)

    // The motion roles from Studio 1.10. Each names an INTENT, not a curve.
    // Always spell them out in full — `StudioAnimation.snappy`, never a bare
    // `.snappy` — because SwiftUI ships its own `Animation.spring`, `.snappy`
    // and `.smooth`, and an implicit member silently binds to Apple's curve.

    /// General transitions, hovers, backgrounds. The same curve as `base`.
    public static let standard = base
    /// Decelerating reveals, entrances, the detail push. The same curve as `out`.
    public static let reveal = out
    /// The universal press-shrink. Quick and bouncy.
    public static let press = Animation.spring(response: 0.26, dampingFraction: 0.62)
    /// Selection and segment changes; less overshoot than `spring`.
    public static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.78)

    /// The single Reduce Motion gate. Returns nil under Reduce Motion, so
    /// `withAnimation(_:)` and `.animation(_:value:)` apply the change
    /// instantly — the Swift counterpart of the CSS layer collapsing every
    /// duration token to 0.01s.
    ///
    ///     @Environment(\.accessibilityReduceMotion) private var reduceMotion
    ///     withAnimation(StudioAnimation.resolve(StudioAnimation.spring, reduceMotion: reduceMotion)) { … }
    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Typography

/// The four families. Names must match the registered PostScript family names
/// of the bundled font files.
public enum StudioFontFamily {
    /// Bounded — wide geometric grotesk. Heroes, page + card titles, wordmark.
    public static let display = "Bounded"
    /// Editorial New italic — the two-tone accent word only. Never uppercase.
    public static let serif = "Editorial New"
    /// Certia — humanist grotesque. All interface and body text.
    public static let body = "Certia"
    /// Space Grotesk — kickers, labels, metadata, data. Always UPPERCASE, wide tracking.
    public static let label = "Space Grotesk"
}

/// The semantic type scale — one case per CSS `.t-*` class.
public enum StudioTextStyle: String, CaseIterable {
    case displayXl = "display-xl"
    case display = "display"
    case title = "title"
    case titleSm = "title-sm"
    case serifAccent = "serif-accent"
    case lead = "lead"
    case body = "body"
    case ui = "ui"
    case uiSm = "ui-sm"
    case kicker = "kicker"
    case label = "label"
    case meta = "meta"
    case mono = "mono"

    public var family: String {
        switch self {
        case .displayXl: return StudioFontFamily.display
        case .display: return StudioFontFamily.display
        case .title: return StudioFontFamily.display
        case .titleSm: return StudioFontFamily.display
        case .serifAccent: return StudioFontFamily.serif
        case .lead: return StudioFontFamily.body
        case .body: return StudioFontFamily.body
        case .ui: return StudioFontFamily.body
        case .uiSm: return StudioFontFamily.body
        case .kicker: return StudioFontFamily.label
        case .label: return StudioFontFamily.label
        case .meta: return StudioFontFamily.label
        case .mono: return StudioFontFamily.label
        }
    }

    /// The desktop maximum — the upper bound of the CSS `clamp()`.
    public var size: CGFloat {
        switch self {
        case .displayXl: return 72
        case .display: return 56
        case .title: return 26
        case .titleSm: return 22
        case .serifAccent: return 56
        case .lead: return 17
        case .body: return 15
        case .ui: return 14
        case .uiSm: return 13
        case .kicker: return 10.5
        case .label: return 10
        case .meta: return 10
        case .mono: return 11
        }
    }

    /// The compact-width minimum — the lower bound of the CSS `clamp()`.
    /// Styles that are not fluid return the same value as `size`, so
    /// `StudioViewport` can interpolate every style without branching.
    public var minSize: CGFloat {
        switch self {
        case .displayXl: return 40
        case .display: return 34
        case .title: return 26
        case .titleSm: return 22
        case .serifAccent: return 56
        case .lead: return 17
        case .body: return 15
        case .ui: return 14
        case .uiSm: return 13
        case .kicker: return 10.5
        case .label: return 10
        case .meta: return 10
        case .mono: return 11
        }
    }

    /// True where the web layer sets a fluid `clamp()` size.
    public var isFluid: Bool {
        switch self {
        case .displayXl: return true
        case .display: return true
        case .title: return false
        case .titleSm: return false
        case .serifAccent: return false
        case .lead: return false
        case .body: return false
        case .ui: return false
        case .uiSm: return false
        case .kicker: return false
        case .label: return false
        case .meta: return false
        case .mono: return false
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .displayXl: return .medium
        case .display: return .medium
        case .title: return .medium
        case .titleSm: return .medium
        case .serifAccent: return .regular
        case .lead: return .regular
        case .body: return .medium
        case .ui: return .medium
        case .uiSm: return .medium
        case .kicker: return .medium
        case .label: return .semibold
        case .meta: return .medium
        case .mono: return .regular
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .displayXl: return 0.98
        case .display: return 1
        case .title: return 1.12
        case .titleSm: return 1.12
        case .serifAccent: return 1
        case .lead: return 1.65
        case .body: return 1.55
        case .ui: return 1.3
        case .uiSm: return 1.3
        case .kicker: return 1.2
        case .label: return 1.2
        case .meta: return 1.2
        case .mono: return 1.4
        }
    }

    /// Tracking in em. Multiply by the point size for `kerning`.
    public var tracking: CGFloat {
        switch self {
        case .displayXl: return -0.03
        case .display: return -0.03
        case .title: return -0.025
        case .titleSm: return -0.022
        case .serifAccent: return -0.01
        case .lead: return 0
        case .body: return -0.005
        case .ui: return -0.008
        case .uiSm: return -0.005
        case .kicker: return 0.16
        case .label: return 0.16
        case .meta: return 0.08
        case .mono: return 0.04
        }
    }

    public var isUppercase: Bool {
        switch self {
        case .displayXl: return false
        case .display: return false
        case .title: return false
        case .titleSm: return false
        case .serifAccent: return false
        case .lead: return false
        case .body: return false
        case .ui: return false
        case .uiSm: return false
        case .kicker: return true
        case .label: return true
        case .meta: return true
        case .mono: return false
        }
    }
}

public enum StudioTokens {
    public static let version = "1.2.0"
}

// MARK: - Accent families

/// The accent, re-pointable. Generated from `primaryFamilies`, the same
/// block the web reads for `data-primary="<family>"` — so a family added
/// to the token file appears on both platforms at once, and neither can
/// carry a hue the other does not have.
///
/// Set one on any subtree and everything built on the accent follows:
///
///     ContentView().studioAccent(.violet)
///
/// `Color.studioAccent` and its siblings stay the generated default (lime).
/// To follow a re-point, paint with `StudioAccentStyle.accent` (and its
/// siblings), which resolve the family from the environment at draw time.
public enum StudioAccentFamily: String, CaseIterable, Sendable {
    case blue
    case sky
    case cyan
    case teal
    case emerald
    case green
    case lime
    case yellow
    case amber
    case orange
    case red
    case pink
    case purple
    case violet
    case indigo

    /// The untouched default.
    public static let `default`: StudioAccentFamily = .lime

    /// Resolved accent ramp for this family, in the given appearance.
    public func ramp(dark: Bool) -> StudioAccentRamp {
        dark ? Self.darkRamps[self]! : Self.lightRamps[self]!
    }

    private static let lightRamps: [StudioAccentFamily: StudioAccentRamp] = [
        .blue: StudioAccentRamp(accent: (0.1385, 0.3996, 0.915, 1), ink: (0.957, 0.9752, 1, 1), soft: (0.1385, 0.3996, 0.915, 0.16), line: (0.0749, 0.3247, 0.8121, 1), active: (0.0293, 0.2577, 0.6929, 1), glow: (0.1385, 0.3996, 0.915, 0.5)),
        .sky: StudioAccentRamp(accent: (0.1321, 0.6407, 0.8905, 1), ink: (0.9462, 0.98, 1, 1), soft: (0.1321, 0.6407, 0.8905, 0.16), line: (0, 0.5304, 0.7626, 1), active: (0, 0.4233, 0.6289, 1), glow: (0.1321, 0.6407, 0.8905, 0.5)),
        .cyan: StudioAccentRamp(accent: (0, 0.7099, 0.8305, 1), ink: (0, 0.0899, 0.1325, 1), soft: (0, 0.7099, 0.8305, 0.16), line: (0, 0.5896, 0.7027, 1), active: (0, 0.471, 0.5707, 1), glow: (0, 0.7099, 0.8305, 0.5)),
        .teal: StudioAccentRamp(accent: (0, 0.7215, 0.6508, 1), ink: (0, 0.0988, 0.0787, 1), soft: (0, 0.7215, 0.6508, 0.16), line: (0, 0.6026, 0.5384, 1), active: (0, 0.4841, 0.4288, 1), glow: (0, 0.7215, 0.6508, 0.5)),
        .emerald: StudioAccentRamp(accent: (0, 0.6562, 0.4439, 1), ink: (0.9477, 0.9848, 0.9649, 1), soft: (0, 0.6562, 0.4439, 0.16), line: (0, 0.5531, 0.3566, 1), active: (0, 0.4499, 0.2771, 1), glow: (0, 0.6562, 0.4439, 0.5)),
        .green: StudioAccentRamp(accent: (0.1715, 0.6664, 0.3057, 1), ink: (0.9541, 0.9836, 0.9567, 1), soft: (0.1715, 0.6664, 0.3057, 0.16), line: (0.0149, 0.5604, 0.2201, 1), active: (0, 0.4549, 0.1478, 1), glow: (0.1715, 0.6664, 0.3057, 0.5)),
        // Lime is the default family, so it carries the exact semantic values
        // (including the 11 Oct --accent-line and --accent-ink contrast fixes):
        // StudioAccentStyle under the default family must equal Color.studioAccent*.
        .lime: StudioAccentRamp(accent: (0.3995, 0.8391, 0.1947, 1), ink: (0, 0.0545, 0.0003, 1), soft: (0.3995, 0.8391, 0.1947, 0.16), line: (0.008, 0.584, 0, 1), active: (0.1654, 0.5522, 0, 1), glow: (0.3995, 0.8391, 0.1947, 0.5)),
        .yellow: StudioAccentRamp(accent: (0.8973, 0.799, 0.108, 1), ink: (0.0944, 0.0671, 0, 1), soft: (0.8973, 0.799, 0.108, 0.16), line: (0.74, 0.6464, 0, 1), active: (0.5851, 0.5005, 0, 1), glow: (0.8973, 0.799, 0.108, 0.5)),
        .amber: StudioAccentRamp(accent: (0.9491, 0.6513, 0.095, 1), ink: (0.1263, 0.0459, 0, 1), soft: (0.9491, 0.6513, 0.095, 0.16), line: (0.7978, 0.5202, 0, 1), active: (0.6429, 0.3983, 0, 1), glow: (0.9491, 0.6513, 0.095, 0.5)),
        .orange: StudioAccentRamp(accent: (0.952, 0.4071, 0.0599, 1), ink: (1, 0.9652, 0.9486, 1), soft: (0.952, 0.4071, 0.0599, 0.16), line: (0.816, 0.3056, 0, 1), active: (0.6732, 0.2171, 0, 1), glow: (0.952, 0.4071, 0.0599, 0.5)),
        .red: StudioAccentRamp(accent: (0.8882, 0.0456, 0.2078, 1), ink: (1, 0.9626, 0.9597, 1), soft: (0.8882, 0.0456, 0.2078, 0.16), line: (0.7759, 0, 0.1394, 1), active: (0.6525, 0, 0.0876, 1), glow: (0.8882, 0.0456, 0.2078, 0.5)),
        .pink: StudioAccentRamp(accent: (0.8857, 0.184, 0.6008, 1), ink: (1, 0.962, 0.9783, 1), soft: (0.8857, 0.184, 0.6008, 0.16), line: (0.7661, 0.0533, 0.5065, 1), active: (0.6375, 0, 0.4123, 1), glow: (0.8857, 0.184, 0.6008, 0.5)),
        .purple: StudioAccentRamp(accent: (0.5788, 0.2057, 0.8706, 1), ink: (0.981, 0.9668, 1, 1), soft: (0.5788, 0.2057, 0.8706, 0.16), line: (0.4994, 0.1235, 0.769, 1), active: (0.4173, 0.0545, 0.6552, 1), glow: (0.5788, 0.2057, 0.8706, 0.5)),
        .violet: StudioAccentRamp(accent: (0.4082, 0.2383, 0.9489, 1), ink: (0.9696, 0.9705, 1, 1), soft: (0.4082, 0.2383, 0.9489, 0.16), line: (0.3491, 0.1614, 0.8468, 1), active: (0.2896, 0.1017, 0.7274, 1), glow: (0.4082, 0.2383, 0.9489, 0.5)),
        .indigo: StudioAccentRamp(accent: (0.2551, 0.3044, 0.8815, 1), ink: (0.9623, 0.9732, 1, 1), soft: (0.2551, 0.3044, 0.8815, 0.16), line: (0.2097, 0.2402, 0.7876, 1), active: (0.1686, 0.1857, 0.6794, 1), glow: (0.2551, 0.3044, 0.8815, 0.5)),
    ]

    private static let darkRamps: [StudioAccentFamily: StudioAccentRamp] = [
        .blue: StudioAccentRamp(accent: (0.2953, 0.5225, 0.9601, 1), ink: (0.957, 0.9752, 1, 1), soft: (0.2953, 0.5225, 0.9601, 0.18), line: (0.1385, 0.3996, 0.915, 1), active: (0.0749, 0.3247, 0.8121, 1), glow: (0.2953, 0.5225, 0.9601, 0.5)),
        .sky: StudioAccentRamp(accent: (0.342, 0.7106, 0.9251, 1), ink: (0, 0.078, 0.1577, 1), soft: (0.342, 0.7106, 0.9251, 0.18), line: (0.1321, 0.6407, 0.8905, 1), active: (0, 0.5304, 0.7626, 1), glow: (0.342, 0.7106, 0.9251, 0.5)),
        .cyan: StudioAccentRamp(accent: (0.2995, 0.7676, 0.8704, 1), ink: (0, 0.0899, 0.1325, 1), soft: (0.2995, 0.7676, 0.8704, 0.18), line: (0, 0.7099, 0.8305, 1), active: (0, 0.5896, 0.7027, 1), glow: (0.2995, 0.7676, 0.8704, 0.5)),
        .teal: StudioAccentRamp(accent: (0.2964, 0.7779, 0.7139, 1), ink: (0, 0.0988, 0.0787, 1), soft: (0.2964, 0.7779, 0.7139, 0.18), line: (0, 0.7215, 0.6508, 1), active: (0, 0.6026, 0.5384, 1), glow: (0.2964, 0.7779, 0.7139, 0.5)),
        .emerald: StudioAccentRamp(accent: (0.2595, 0.726, 0.5387, 1), ink: (0, 0.0982, 0.0369, 1), soft: (0.2595, 0.726, 0.5387, 0.18), line: (0, 0.6562, 0.4439, 1), active: (0, 0.5531, 0.3566, 1), glow: (0.2595, 0.726, 0.5387, 0.5)),
        .green: StudioAccentRamp(accent: (0.3565, 0.7345, 0.4278, 1), ink: (0, 0.0946, 0.0089, 1), soft: (0.3565, 0.7345, 0.4278, 0.18), line: (0.1715, 0.6664, 0.3057, 1), active: (0.0149, 0.5604, 0.2201, 1), glow: (0.3565, 0.7345, 0.4278, 0.5)),
        .lime: StudioAccentRamp(accent: (0.4843, 0.9494, 0.285, 1), ink: (0, 0.0574, 0, 1), soft: (0.4843, 0.9494, 0.285, 0.18), line: (0.2593, 0.7652, 0.2167, 1), active: (0.3995, 0.8391, 0.1947, 1), glow: (0.4843, 0.9494, 0.285, 0.5)),
        .yellow: StudioAccentRamp(accent: (0.916, 0.8355, 0.3445, 1), ink: (0.0944, 0.0671, 0, 1), soft: (0.916, 0.8355, 0.3445, 0.18), line: (0.8973, 0.799, 0.108, 1), active: (0.74, 0.6464, 0, 1), glow: (0.916, 0.8355, 0.3445, 0.5)),
        .amber: StudioAccentRamp(accent: (0.9683, 0.7142, 0.3292, 1), ink: (0.1263, 0.0459, 0, 1), soft: (0.9683, 0.7142, 0.3292, 0.18), line: (0.9491, 0.6513, 0.095, 1), active: (0.7978, 0.5202, 0, 1), glow: (0.9683, 0.7142, 0.3292, 0.5)),
        .orange: StudioAccentRamp(accent: (0.9877, 0.5206, 0.2939, 1), ink: (0.1472, 0.0229, 0, 1), soft: (0.9877, 0.5206, 0.2939, 0.18), line: (0.952, 0.4071, 0.0599, 1), active: (0.816, 0.3056, 0, 1), glow: (0.9877, 0.5206, 0.2939, 0.5)),
        .red: StudioAccentRamp(accent: (0.9495, 0.3209, 0.3474, 1), ink: (1, 0.9626, 0.9597, 1), soft: (0.9495, 0.3209, 0.3474, 0.18), line: (0.8882, 0.0456, 0.2078, 1), active: (0.7759, 0, 0.1394, 1), glow: (0.9495, 0.3209, 0.3474, 0.5)),
        .pink: StudioAccentRamp(accent: (0.9399, 0.3679, 0.6764, 1), ink: (1, 0.962, 0.9783, 1), soft: (0.9399, 0.3679, 0.6764, 0.18), line: (0.8857, 0.184, 0.6008, 1), active: (0.7661, 0.0533, 0.5065, 1), glow: (0.9399, 0.3679, 0.6764, 0.5)),
        .purple: StudioAccentRamp(accent: (0.6594, 0.3804, 0.9229, 1), ink: (0.981, 0.9668, 1, 1), soft: (0.6594, 0.3804, 0.9229, 0.18), line: (0.5788, 0.2057, 0.8706, 1), active: (0.4994, 0.1235, 0.769, 1), glow: (0.6594, 0.3804, 0.9229, 0.5)),
        .violet: StudioAccentRamp(accent: (0.4952, 0.4105, 0.9931, 1), ink: (0.9696, 0.9705, 1, 1), soft: (0.4952, 0.4105, 0.9931, 0.18), line: (0.4082, 0.2383, 0.9489, 1), active: (0.3491, 0.1614, 0.8468, 1), glow: (0.4952, 0.4105, 0.9931, 0.5)),
        .indigo: StudioAccentRamp(accent: (0.3631, 0.4501, 0.9367, 1), ink: (0.9623, 0.9732, 1, 1), soft: (0.3631, 0.4501, 0.9367, 0.18), line: (0.2551, 0.3044, 0.8815, 1), active: (0.2097, 0.2402, 0.7876, 1), glow: (0.3631, 0.4501, 0.9367, 0.5)),
    ]
}

/// One family's resolved accent colours. Component values are stored as
/// sRGB tuples because the OKLCH → sRGB conversion happens at build time,
/// exactly as it does for every other generated colour.
public struct StudioAccentRamp: Sendable {
    public let accent: Color
    public let ink: Color
    public let soft: Color
    public let line: Color
    public let active: Color
    public let glow: Color

    init(
        accent: (Double, Double, Double, Double),
        ink: (Double, Double, Double, Double),
        soft: (Double, Double, Double, Double),
        line: (Double, Double, Double, Double),
        active: (Double, Double, Double, Double),
        glow: (Double, Double, Double, Double)
    ) {
        self.accent = Color(.sRGB, red: accent.0, green: accent.1, blue: accent.2, opacity: accent.3)
        self.ink = Color(.sRGB, red: ink.0, green: ink.1, blue: ink.2, opacity: ink.3)
        self.soft = Color(.sRGB, red: soft.0, green: soft.1, blue: soft.2, opacity: soft.3)
        self.line = Color(.sRGB, red: line.0, green: line.1, blue: line.2, opacity: line.3)
        self.active = Color(.sRGB, red: active.0, green: active.1, blue: active.2, opacity: active.3)
        self.glow = Color(.sRGB, red: glow.0, green: glow.1, blue: glow.2, opacity: glow.3)
    }
}

// MARK: - Composition

/// The arrangement layer, generated from `composition` in the token file.
/// Colour and type say what things look like; these say how a screen is put
/// together — how many scale steps it may mix, how tall the one focal
/// moment is, what protects text on imagery, and which rhythm breaks are
/// sanctioned. Identical values reach the web as `--focal-*`, `--hero-h-*`,
/// `--scrim-*` and `--rhythm-*`.
public enum StudioComposition: Sendable {
    // focal
    /// The one moment. Full-bleed, image-led, display type.
    public static let focalHero: CGFloat = 1
    /// Cards and tiles that carry a title and an image.
    public static let focalFeature: CGFloat = 2
    /// Rows, tables, stat cards. Figures, not decoration.
    public static let focalDense: CGFloat = 3
    // heroHeight
    public static let heroHeightCompact: CGFloat = 340
    public static let heroHeightMedium: CGFloat = 400
    public static let heroHeightWide: CGFloat = 420
    // scrim
    /// Opacity at the anchored edge, fading to zero.
    public static let scrimIntensity: CGFloat = 0.82
    /// Fraction of the frame the gradient spans.
    public static let scrimCoverage: CGFloat = 0.68
    /// The scrim gradient's base. Black in both themes: it darkens a photograph, it does not tint it.
    public static let scrimInk = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    /// Text over imagery is always light ink, both themes.
    public static let scrimOnImageInk = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
    /// Meta lines over imagery.
    public static let scrimOnImageInkMuted = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.72)
    // rhythm
    /// Between major sections on an editorial page.
    public static let rhythmSectionGap: CGFloat = 64
    public static let rhythmSectionGapCompact: CGFloat = 44
    /// Compressed spacing inside dense detail rows.
    public static let rhythmDetailRow: CGFloat = 10
    /// The reading measure for editorial columns.
    public static let rhythmMeasure: CGFloat = 680
}
