/* ============================================================
   StudioKitTests

   UI-free and deterministic: token presence and values, font
   registration, viewport banding, the toast centre's model, the
   accent ramps and the Reduce Motion gate. Nothing renders, so the
   suite runs under plain `swift test` on a Mac with no simulator.

   Run: swift test --package-path platform/studio/packages/swift
   ============================================================ */

import XCTest
import SwiftUI
import CoreText
@testable import StudioKit

// MARK: - Tokens

final class StudioTokenTests: XCTestCase {

    /// Resolving a colour proves the token exists and yields a value. The
    /// categorical viz steps are theme-independent, so their resolution is
    /// deterministic whatever appearance the test host runs in.
    private func resolved(_ color: Color) -> Color.Resolved {
        color.resolve(in: EnvironmentValues())
    }

    /// The dynamic (UIColor / NSColor) and static (Color(.sRGB)) paths can
    /// round differently in the last float bits, so compare with tolerance.
    private func assertClose(_ a: Color.Resolved, _ b: Color.Resolved, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.red, b.red, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(a.green, b.green, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(a.opacity, b.opacity, accuracy: 0.002, file: file, line: line)
    }

    func testSemanticColoursExist() {
        let colours: [Color] = [
            .studioBg, .studioBgEdge, .studioSurface, .studioSurface2, .studioSurface3,
            .studioBorder, .studioBorderStrong,
            .studioText, .studioText2, .studioText3, .studioText4,
            .studioAccent, .studioAccentInk, .studioAccentSoft, .studioAccentLine,
            .studioAccentGlow, .studioAccentActive,
            .studioGlassBg, .studioGlassBorder, .studioScrim,
            .studioCanvasBg, .studioCanvasGrid, .studioCanvasGridMajor,
            .studioCanvasArtboard, .studioCanvasSelection, .studioCanvasSelectionSoft,
            .studioIdentityBg, .studioIdentityInk, .studioIdentityRing,
        ]
        for colour in colours {
            XCTAssertGreaterThan(resolved(colour).opacity, 0)
        }
    }

    func testStatusColoursAndSoftVariantsExist() {
        let pairs: [(Color, Color)] = [
            (.studioError, .studioErrorSoft),
            (.studioSuccess, .studioSuccessSoft),
            (.studioWarning, .studioWarningSoft),
            (.studioInfo, .studioInfoSoft),
        ]
        for (solid, soft) in pairs {
            let s = resolved(solid)
            let f = resolved(soft)
            XCTAssertEqual(s.opacity, 1, accuracy: 0.001)
            // Soft is the same hue at 12% (light) / 16% (dark).
            XCTAssertLessThan(f.opacity, 0.2)
            XCTAssertGreaterThan(f.opacity, 0.1)
        }
    }

    func testChartPaletteExists() {
        XCTAssertEqual(Color.studioVizCategorical.count, 6, "--viz-1…6: six is the ceiling")

        let rotation = Color.studioVizCategorical.map(resolved)
        XCTAssertEqual(Set(rotation).count, 6, "every categorical step is distinct")

        // The rotation is the documented palette steps, in order.
        let palette: [Color] = [
            Color.StudioPalette.blue500, Color.StudioPalette.violet400, Color.StudioPalette.teal500,
            Color.StudioPalette.amber500, Color.StudioPalette.pink500, Color.StudioPalette.cyan600,
        ]
        for (step, expected) in zip(rotation, palette.map(resolved)) {
            assertClose(step, expected)
        }
        assertClose(resolved(.studioVizOther), resolved(Color.StudioPalette.neutral400))

        // Lime is NOT in the rotation; it is reserved for the highlight.
        XCTAssertFalse(rotation.contains(resolved(.studioVizHighlight)))
        XCTAssertGreaterThan(resolved(.studioVizGrid).opacity, 0)
    }

    func testSpacingScale() {
        // Mirrors the CSS 4/8/12/16/20/24/32/40/48/64 scale; there is no 28.
        XCTAssertEqual(
            [StudioSpace.s1, StudioSpace.s2, StudioSpace.s3, StudioSpace.s4, StudioSpace.s5,
             StudioSpace.s6, StudioSpace.s8, StudioSpace.s10, StudioSpace.s12, StudioSpace.s16],
            [4, 8, 12, 16, 20, 24, 32, 40, 48, 64]
        )
    }

    func testRadiusAndLayoutMetrics() {
        XCTAssertLessThan(StudioRadius.xs, StudioRadius.sm)
        XCTAssertLessThan(StudioRadius.sm, StudioRadius.md)
        XCTAssertLessThan(StudioRadius.md, StudioRadius.lg)
        XCTAssertLessThan(StudioRadius.lg, StudioRadius.xl)
        XCTAssertGreaterThanOrEqual(StudioLayout.tapTarget, 44, "never ship a target under 44pt")
        XCTAssertGreaterThanOrEqual(StudioLayout.dockAction, StudioLayout.tapTarget)
        XCTAssertGreaterThan(StudioLayout.pillHeight, StudioLayout.controlHeight)
    }

    func testEveryTextStyleHasAFamilyAndASize() {
        let families = [
            StudioFontFamily.display, StudioFontFamily.serif,
            StudioFontFamily.body, StudioFontFamily.label,
        ]
        for style in StudioTextStyle.allCases {
            XCTAssertTrue(families.contains(style.family), "\(style) uses an unbundled family")
            XCTAssertGreaterThan(style.size, 0)
            XCTAssertLessThanOrEqual(style.minSize, style.size)
            XCTAssertGreaterThan(style.lineHeight, 0)
        }
    }

    func testUppercaseStylesAreTheLabelFamilyOnly() {
        // `.meta`, `.label` and `.kicker` are uppercase: never for
        // sentences, emails or URLs. Pin the set so it can't grow silently.
        let upper = StudioTextStyle.allCases.filter(\.isUppercase)
        XCTAssertEqual(Set(upper), [.kicker, .label, .meta])
    }
}

// MARK: - Fonts

final class StudioFontTests: XCTestCase {

    private static let families = [
        StudioFontFamily.display,   // Bounded
        StudioFontFamily.serif,     // Editorial New
        StudioFontFamily.body,      // Certia
        StudioFontFamily.label,     // Space Grotesk
    ]

    func testFontFilesAreBundled() {
        for name in ["Bounded-Variable", "EditorialNew-Italic", "SpaceGrotesk-Variable", "Certia-Regular", "Certia-Bold"] {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf")
                ?? Bundle.module.url(forResource: name, withExtension: "otf")
            XCTAssertNotNil(url, "\(name) is missing from the StudioKit bundle")
        }
    }

    func testFamiliesRegisterAndResolveByName() {
        StudioFonts.register()
        StudioFonts.register() // idempotent: a second call must be harmless

        for family in Self.families {
            let attributes = [kCTFontFamilyNameAttribute as String: family] as CFDictionary
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
            let matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor]
            XCTAssertFalse(matches?.isEmpty ?? true, "\(family) did not register with Core Text")

            // The family name SwiftUI's `.custom(_:)` resolves must be the
            // registered one, or text silently falls back to the system font.
            let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, family)
        }
    }

    func testLineSpacingNeverNegative() {
        StudioFonts.register()
        for style in StudioTextStyle.allCases {
            let spacing = studioLineSpacing(family: style.family, size: style.size, lineHeight: style.lineHeight)
            XCTAssertGreaterThanOrEqual(spacing, 0)
            XCTAssertLessThan(spacing, style.size, "\(style): extra leading larger than the type itself")
        }
    }
}

// MARK: - Viewport

final class StudioViewportTests: XCTestCase {

    func testWidthBandsMatchTheStylesheet() {
        // The CSS breakpoints are 720 and 1100; the Swift bands must agree.
        XCTAssertEqual(StudioViewport(width: 0), .compact)
        XCTAssertEqual(StudioViewport(width: 719), .compact)
        XCTAssertEqual(StudioViewport(width: 720), .medium)
        XCTAssertEqual(StudioViewport(width: 1099), .medium)
        XCTAssertEqual(StudioViewport(width: 1100), .expanded)
        XCTAssertEqual(StudioViewport(width: 4000), .expanded)
    }
}

// MARK: - Toasts

final class StudioToastCenterTests: XCTestCase {

    @MainActor
    func testShowAppendsAndDismissRemoves() {
        // duration 0 disables auto-dismiss, keeping the test synchronous.
        let center = StudioToastCenter(duration: 0)
        XCTAssertTrue(center.toasts.isEmpty)

        center.show("Saved.")
        center.show("Published.", variant: .success)
        XCTAssertEqual(center.toasts.map(\.message), ["Saved.", "Published."])

        let first = center.toasts[0]
        center.dismiss(first)
        XCTAssertEqual(center.toasts.map(\.message), ["Published."])

        // Dismissing something already gone is a no-op, not a crash.
        center.dismiss(first)
        XCTAssertEqual(center.toasts.count, 1)
    }
}

// MARK: - Accent, motion, haptics

final class StudioAccentTests: XCTestCase {

    func testEveryFamilyHasBothRamps() {
        for family in StudioAccentFamily.allCases {
            _ = family.ramp(dark: false)
            _ = family.ramp(dark: true)
        }
        XCTAssertEqual(StudioAccentFamily.default, .lime)
    }

    func testDefaultFamilyMatchesTheSemanticAccent() {
        // The default ramp must carry the contrast-fixed semantic values,
        // or StudioAccentStyle and Color.studioAccent* would disagree.
        var light = EnvironmentValues()
        light.colorScheme = .light
        let ramp = StudioAccentFamily.lime.ramp(dark: false)
        XCTAssertEqual(ramp.line.resolve(in: light), Color(.sRGB, red: 0.008, green: 0.584, blue: 0, opacity: 1).resolve(in: light))
        XCTAssertEqual(ramp.ink.resolve(in: light), Color(.sRGB, red: 0, green: 0.0545, blue: 0.0003, opacity: 1).resolve(in: light))
    }
}

final class StudioMotionTests: XCTestCase {

    func testReduceMotionGateRemovesAnimation() {
        XCTAssertNil(StudioAnimation.resolve(StudioAnimation.spring, reduceMotion: true))
        XCTAssertNotNil(StudioAnimation.resolve(StudioAnimation.spring, reduceMotion: false))
    }
}

final class StudioHapticsTests: XCTestCase {

    @MainActor
    func testDisabledHapticsAreInert() {
        let haptics = StudioHaptics(isEnabled: false)
        for feedback in [StudioHaptics.Feedback.selection, .light, .success, .warning, .error] {
            haptics.play(feedback) // must not crash on a host without a Taptic Engine
        }
        XCTAssertFalse(haptics.isEnabled)
    }
}
