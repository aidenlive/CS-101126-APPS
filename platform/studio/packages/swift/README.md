# StudioKit

The Studio design system for SwiftUI. Same tokens as the web layer, same
rules, generated from the same source.

```swift
import StudioKit

StudioFonts.register()          // once, in App.init()

StudioCard {
    StudioTwoToneTitle("A working ", accent: "collection.")
    StudioButton("Save", variant: .primary) { save() }
}
```

## What is generated and what is written by hand

| File | Source |
|---|---|
| `Generated/StudioTokens.swift` | **Generated** from `tokens/studio.tokens.json` |
| `StudioFonts.swift` | Hand-written — font registration |
| `StudioText.swift` | Hand-written — the type scale as view modifiers |
| `StudioGlass.swift` | Hand-written — the material |
| `StudioComponents.swift` | Hand-written — the atoms |
| `StudioControls.swift` | Hand-written — segmented, toggles, choices, fields |
| `StudioSurfaces.swift` | Hand-written — page heads, list shapes, tables, dialogs |
| `StudioFeedback.swift` | Hand-written — the toast centre |
| `StudioShell.swift` | Hand-written — the adaptive frame and its chrome |
| `StudioViewport.swift` | Hand-written — the width bands |

Run `npm run build:tokens` at the repository root after any token change.
Never edit the generated file: it is overwritten without warning.

## Colour

Semantic colours are `Color.studio*` and resolve light or dark
automatically — from the trait environment on UIKit platforms and from the
effective `NSAppearance` on native macOS — exactly as the CSS custom
properties do:

```swift
Text("Hello").foregroundStyle(Color.studioText2)
```

The raw palette lives under `Color.StudioPalette` and exists only for
building new semantic tokens or data-visualisation scales. **Views should
never reference it directly** — that is the same rule the web linter
enforces.

## Width, not size class

SwiftUI has no media queries, and size classes do not match the CSS
breakpoints — an iPad in a 700pt split view reports `.regular` while the
stylesheet is already in rail mode. So StudioKit measures width and maps it
through the *same* two generated thresholds:

```swift
ContentView().studioViewport()      // once, at the root of a scene

@Environment(\.studioViewport) private var viewport
```

Three bands, matching `--bp-tablet: 720` and `--bp-desktop: 1100` exactly:

| Band | Width | Shell |
|---|---|---|
| `.compact` | < 720pt | Floating tab pill + FAB, no sidebar |
| `.medium` | 720–1099pt | 76pt icon rail |
| `.expanded` | ≥ 1100pt | Full 256pt sidebar |

This also drives fluid display type. The web sizes headlines with
`clamp(min, vw, max)`; iOS has no viewport unit, so the same two bounds —
generated from `fontSizeMin` and `fontSize` in the token source — are
interpolated across the three bands instead. A 72pt hero would swamp a
phone, and shipping it at 40pt on a Mac would look timid.

Non-fluid styles return their single size unchanged, exactly as the CSS
does.

## Version sensitivity

`StudioGlass.swift` is the only file that depends on the OS version. On
iOS 26+ it uses the system Liquid Glass effect; below that it composes a
SwiftUI material with the hairline and layered shadow from the tokens.

Every component reaches the material through `.studioGlass()`, so if
Apple's API changes, that one modifier is the only thing to update.

## Motion

`StudioAnimation` maps the three CSS easings to their closest native
equivalents. SwiftUI has no cubic-Bézier initialiser, so these are
approximations of the curves rather than exact ports — `.spring` in
particular is tuned by feel to match the CSS overshoot.

StudioKit's own components read `accessibilityReduceMotion`: with it on,
the press shrink becomes a dim, the segmented indicator and tab pill stop
springing, toasts fade instead of rising, the sidebar fades instead of
sliding, and the hover card no longer lifts. Honour the same setting in
your own animations. The CSS layer collapses its duration tokens
automatically; SwiftUI does not, so outside StudioKit that is on the caller.

## Type size

`.studioText(_:)` scales with Dynamic Type exactly once (through
`@ScaledMetric`); `.studioText(_:scaled: false)` is a truly fixed size.
Components size to at least their spec height (`minHeight`) and grow at
large accessibility sizes instead of clipping.

## Buttons

`StudioButton` dims to 45% under `.disabled(true)` and takes an optional
`isLoading:` that swaps the icon for a spinner and ignores taps:

```swift
StudioButton("Save", systemImage: "checkmark", variant: .primary, isLoading: isSaving) { save() }
    .disabled(!canSave)
```
