// swift-tools-version: 5.9
import PackageDescription

/*
 StudioKit — the Studio design system for SwiftUI.

 Tools version is 5.9 deliberately, matching the demo's Playgrounds manifest.
 Moving to 6.0 would require Xcode 16 AND switch the package into the Swift 6
 language mode, whose strict-concurrency checking this code has not been
 audited against. Bump it as a deliberate piece of work, not incidentally.

 Deployment target is iOS 17 so the package is usable in existing apps.
 The Liquid Glass material is adopted through `if #available(iOS 26.0, *)`
 inside `StudioGlass.swift`; below that it falls back to an equivalent
 SwiftUI material; on visionOS it uses the platform glass. That is the only
 version-sensitive code in the package.

 Colour, spacing, radius, motion and type tokens are GENERATED into
 Sources/StudioKit/Generated/StudioTokens.swift from tokens/studio.tokens.json.
 Run `npm run build:tokens` at the repository root to regenerate them.
 */
let package = Package(
    name: "StudioKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        // `.v1` because tools version 5.9 has no `.v2` (the Cardsite app
        // sets its own visionOS 2 floor). StudioGlass uses the platform's
        // glassBackgroundEffect there: visionOS has no Liquid Glass API.
        .visionOS(.v1),
    ],
    products: [
        .library(name: "StudioKit", targets: ["StudioKit"]),
    ],
    targets: [
        .target(
            name: "StudioKit",
            resources: [
                // The four families are bundled with the package, so a
                // consuming app needs no font setup beyond calling
                // StudioFonts.register() once at launch.
                .process("Resources/Fonts"),
            ]
        ),
        // UI-free, deterministic checks that run under `swift test` on a
        // Mac: token presence, font registration, viewport bands, toasts,
        // the accent ramps and the Reduce Motion gate.
        .testTarget(
            name: "StudioKitTests",
            dependencies: ["StudioKit"]
        ),
    ]
)
