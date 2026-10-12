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
| `StudioHaptics.swift` | Hand-written — haptic feedback (UIKit, AppKit, no-op) |
| `StudioLayouts.swift` | Hand-written — `Split`, `Switcher`, `Frame` layouts |
| `StudioCollectionBar.swift` | Hand-written — filters · search · sort · view band |
| `StudioComposition.swift` | Hand-written — remote image, scrim, hero, entrance |
| `StudioAccount.swift` | Hand-written — account button, sheet and rows |
| `StudioEditorShell.swift` | Hand-written — document and canvas editor shells |
| `StudioDock.swift` | Hand-written — compact bottom dock (pre-iOS 26 / macOS) |
| `StudioAccentTheme.swift` | Hand-written — accent re-pointing |
| `Previews/` | DEBUG-only `#Preview`s |

Run `npm run build:tokens` at the repository root after any token change.
Never edit the generated file: it is overwritten without warning.

> **Hand-maintained until the generator catches up.** The canonical
> `Generated/StudioTokens.swift` carries changes the upstream `build.mjs`
> does not emit yet: the AppKit `dynamicColor` (macOS dark mode), the
> 11 Oct contrast-fixed text, accent-line and status values, the dataviz
> colours (`studioViz*`), the canvas and identity colours, the 1.10
> layout metrics and motion roles, `StudioAccentFamily` and
> `StudioComposition`. Port these into the generator before regenerating,
> or they are lost.

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

## Glass and Reduce Transparency

`.studioGlass()` is for floating chrome only, never the content layer. With
Reduce Transparency on, every glass call (Liquid Glass on 26+, the material
fallback below it) renders as the opaque `studioSurface` with a
`studioBorderStrong` hairline, so nothing scrolls visibly behind text.

```swift
.studioGlass()                                         // pill
.studioGlass(cornerRadius: StudioRadius.lg)            // panel
.studioGlass(in: Circle(), tint: .studioAccent, interactive: true)  // the one create affordance
StudioGlassContainer { … }  // + .studioGlassMorph(id:in:) on members
```

## Charts

The dataviz palette is `Color.studioViz1…6` (fixed rotation, never more than
six), `studioVizHighlight` for the one "you / current" series,
`studioVizOther` for the grouped remainder and `studioVizGrid` for axes and
gridlines. Status colours never encode data.

```swift
Chart(series) { … }
    .chartForegroundStyleScale(domain: names, range: Color.studioVizCategorical)
```

## Haptics

```swift
@StateObject private var haptics = StudioHaptics(isEnabled: prefs.haptics)
RootView().environment(\.studioHaptics, haptics)

@Environment(\.studioHaptics) private var haptics
haptics.play(.success)   // .selection, .light, .success, .warning, .error
```

UIKit feedback generators on iPhone and iPad; `NSHapticFeedbackManager` on a
Mac (Force Touch trackpads only); a no-op elsewhere. One feedback per user
action, and only for things the user did.

## Accent re-pointing

`.studioAccent(.violet)` re-points a subtree. `Color.studioAccent*` stay the
default (lime); paint with `StudioAccentStyle.accent` / `.ink` / `.soft` /
`.line` / `.active` / `.glow` where a re-point should be honoured.

## Tests

```sh
swift test --package-path platform/studio/packages/swift
```

`Tests/StudioKitTests` checks that the tokens exist (semantic, status and soft
variants, the chart palette, spacing and radius), that the four families
register and resolve by name, the viewport bands, the toast centre, the accent
ramps and the Reduce Motion gate. Nothing renders, so it needs no simulator.

## Inventory

Every public view, modifier and style. Signatures are abbreviated; defaults
are omitted.

### Tokens

| API | Usage |
|---|---|
| `Color.studio*` | Semantic colours, light/dark: `bg`, `bgEdge`, `surface…3`, `border(Strong)`, `text…4`, `accent(Ink/Soft/Line/Glow/Active)`, `error/success/warning/info` + `…Soft`, `code*`, `glassBg/Border`, `scrim`, `canvas*`, `identity*` |
| `Color.studioViz1…6`, `studioVizHighlight`, `studioVizOther`, `studioVizGrid`, `studioVizCategorical` | Chart colours: `.foregroundStyle(Color.studioViz1)` |
| `Color.StudioPalette.*` | Raw palette. Never in views |
| `StudioSpace.s1…s16` | Spacing: `.padding(StudioSpace.s4)` |
| `StudioRadius.xs…xl, .pill` | Corner radii: `RoundedRectangle(cornerRadius: StudioRadius.lg)` |
| `StudioLayout.*` | `floatInset`, `pillHeight`, `controlHeight`, `dockAction`, `tapTarget`, sidebar widths, breakpoints |
| `StudioDuration.fast/med/slow` | Durations in seconds |
| `StudioAnimation.base/out/spring/standard/reveal/press/snappy` | `withAnimation(StudioAnimation.spring) { … }` |
| `StudioAnimation.resolve(_:reduceMotion:)` | `withAnimation(StudioAnimation.resolve(.spring…, reduceMotion: rm))`: nil under Reduce Motion |
| `StudioComposition.*` | Focal levels, hero heights, scrim, rhythm (`rhythmMeasure`) |
| `StudioAccentFamily`, `StudioAccentRamp` | `StudioAccentFamily.violet.ramp(dark:)` |
| `StudioFontFamily.*`, `StudioTextStyle` | Family names and the type scale |
| `StudioFonts.register()` | Once in `App.init()` |

### Text

| API | Usage |
|---|---|
| `.studioText(_:scaled:)` | `Text("Links").studioText(.title)` |
| `.studioMuted()` | Muted (`text3`) ink |
| `StudioTwoToneTitle(_:accent:style:)` | `StudioTwoToneTitle("Your ", accent: "links.")` |
| `StudioKicker(_:)` | Uppercase kicker with accent dot |
| `StudioTextStyle.resolvedSize(for:)` | Point size for a viewport band |

### Components and controls

| API | Usage |
|---|---|
| `StudioButton(_:systemImage:variant:isLoading:action:)` | `StudioButton("Save", variant: .primary, isLoading: saving) { … }`; variants `.primary .ghost .outline .destructive .danger` |
| `StudioButtonStyle(_:)` | `.buttonStyle(StudioButtonStyle(.outline))` on `Link` / `ShareLink` / `Menu`: the `StudioButton` look for system controls |
| `StudioPressStyle(scale:)` | `.buttonStyle(StudioPressStyle())`: press shrink (dim under Reduce Motion) |
| `StudioChip(_:count:isSelected:action:)` | Filter chip |
| `StudioCard(flush:hover:selected:radius:content:)` | Opaque content surface; already padded |
| `StudioStatusPill(_:tone:)` | `StudioStatusPill("Live", tone: .success)` |
| `StudioBanner(lead:message:tone:)` | Inline banner |
| `StudioBanner(lead:message:tone:onDismiss:)` | Dismissible banner |
| `StudioBadge(_:neutral:)` | Count badge |
| `StudioEmptyState(systemImage:title:accent:message:compact:actions:)` | Empty state with actions |
| `StudioTextField(_:text:placeholder:help:errorMessage:)` | Labelled field |
| `StudioIconButton(systemImage:label:isActive:action:)` | Icon-only button with VoiceOver label |
| `StudioComposeButton(_:systemImage:isCompact:action:)` | Create button |
| `StudioFab(systemImage:label:action:)` | Floating action |
| `StudioSegment(value:label:systemImage:)` | A segment/option value |
| `StudioSegmented(label:selection:segments:iconsOnly:)` | Segmented control |
| `StudioToggleRow(_:help:isOn:)` | Switch row |
| `StudioChoiceRow(_:help:style:isSelected:action:)`, `StudioChoiceGroup(_:content:)` | Checkbox/radio rows |
| `StudioSearchField(text:placeholder:label:)` | Pill search field |
| `StudioSelect(label:selection:options:)` | Native-menu select |
| `StudioKbd(_:)` | Keyboard key cap |
| `StudioCollectionBar(filters:filterCounts:filter:searchPlaceholder:search:sortOptions:sort:viewModes:viewMode:)` | Filters · search · sort · view as one band |

### Surfaces and layout

| API | Usage |
|---|---|
| `StudioPageHead(kicker:title:accent:actions:)` | Page heading with actions |
| `StudioPageHead(kicker:title:accent:description:actions:)` | …with a description line |
| `StudioSectionHeader(_:note:)` | Section label |
| `StudioListRow(title:meta:systemImage:isSelected:action:)` | ROW list shape |
| `StudioMediaCard(kicker:title:meta:systemImage:action:)` | CARD list shape |
| `StudioColumn(id:title:isNumeric:value:)`, `StudioTable(caption:columns:rows:)` | Data table |
| `StudioConfirmDialog(title:message:confirmTitle:cancelTitle:isDestructive:onConfirm:onCancel:)` | Confirm card |
| `.studioConfirm(item:dialog:)`, `.studioConfirm(isPresented:dialog:)` | Present the confirm card over a scrim |
| `StudioSplit(fraction:spacing:minSide:)` | `StudioSplit(fraction: 0.4) { A(); B() }`: two panes, stacks when narrow |
| `StudioSwitcher(threshold:spacing:)` | `StudioSwitcher { Tile(); Tile(); Tile() }`: one row or all stacked |
| `StudioFrame(ratio:cornerRadius:content:)` | Fixed-ratio media well |
| `StudioRemoteImage(url:contentMode:)` | Async image with loading/failure states |
| `StudioProtectionScrim(intensity:coverage:edge:)` | Gradient for text on imagery |
| `.studioOnImage(muted:)` | Light ink over imagery |
| `StudioHero(kicker:title:accent:meta:affordance:action:image:trailing:)`, `StudioHero(imageURL:…)` | The one focal moment per screen |
| `.studioEntrance(delay:)` / `StudioEntrance` | Rise-and-fade entrance (none under Reduce Motion) |
| `StudioViewport`, `.studioViewport()`, `.studioViewport(_:)`, `@Environment(\.studioViewport)` | Width bands; `contentPadding`, `sectionGap` |

### Chrome

| API | Usage |
|---|---|
| `.studioGlass(cornerRadius:)`, `.studioGlass(cornerRadius:tint:interactive:)`, `.studioGlass(cornerRadius:interactive:)`, `.studioGlass(in:tint:interactive:)` | Glass for floating chrome only |
| `StudioGlassContainer(spacing:content:)`, `.studioGlassMorph(id:in:)` | Grouped, morphing glass |
| `.studioFloatInset()`, `.studioElevation(.flat/.raised)` | Float inset; opaque-surface shadow tiers |
| `StudioAppShell(selection:destinations:brand:brandGlyph:composeTitle:onCompose:content:sidebarFooter:)`, `StudioNavDestination`, `StudioNavItem` | The adaptive Studio shell |
| `StudioTopbar(page:mark:actions:)`, `StudioScreen(page:mark:content:actions:)`, `StudioActionsPill`, `StudioSearchPill` | Topbar chrome |
| `StudioAvatar(initial:label:action:)` | Accent avatar button (original) |
| `StudioAvatar(initial:name:size:presence:)` | Identity portrait (`.xs…xl`, `.online/.busy/.away`) |
| `StudioAccountButton(initial:name:label:showsCaret:action:)` | Glass account pill |
| `StudioAccountConfig(name:email:initial:extraRows:)`, `StudioAccountSheet(config:onSignOut:navRows:)`, `StudioAccountRow(systemImage:title:detail:isDestructive:action:)`, `StudioOverflowNavRows(destinations:selection:)` | Account sheet |
| `StudioWorkspaceButton(name:meta:glyph:isRail:action:)` | Sidebar workspace switcher |
| `StudioDock(selection:items:state:searchTitle:onSearch:onCancel:actionTitle:actionSystemImage:onAction:)`, `StudioDockItem(tag:title:systemImage:selectedSystemImage:)` | Compact dock where the system tab bar isn't available |
| `StudioDocumentEditorShell(measure:toolbar:content:)` | Writing column under a glass format bar |
| `StudioCanvasShell(zoomLabel:onZoomIn:onZoomOut:tools:inspector:canvas:)`, `StudioToolButton`, `StudioCanvasGrid(spacing:scale:)`, `StudioArtboard` | Canvas editor |

### Feedback, haptics, accent

| API | Usage |
|---|---|
| `StudioToastCenter(duration:)`, `.studioToasts(_:)`, `StudioToast`, `StudioToastView` | `toasts.show("Saved", variant: .success)`; posts a VoiceOver announcement |
| `StudioHaptics(isEnabled:)`, `@Environment(\.studioHaptics)` | `haptics.play(.selection)` |
| `.studioAccent(_:)`, `@Environment(\.studioAccentFamily)`, `StudioAccentStyle.accent…glow` | Accent re-pointing |
