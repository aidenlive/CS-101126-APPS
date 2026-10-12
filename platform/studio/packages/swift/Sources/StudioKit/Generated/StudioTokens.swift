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
