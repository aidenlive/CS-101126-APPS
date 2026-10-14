# Liquid Glass brief for the Cardsite design-polish pass

As of 14 Oct 2026. iOS 26 shipped Sept 2025 and iOS 27 shipped 14 Sep 2026. Deployment targets are iOS 18 and macOS 15.

**Labels.** **VERIFIED** means read on an official Apple page; the URL is given. **REPORTED** means from named press coverage, linked. **UNVERIFIED** means observed or remembered and not confirmed by a source fetched for this brief. Check UNVERIFIED items on a device before relying on them.

**Method.** Apple doc pages were read through the DocC JSON endpoint (`developer.apple.com/tutorials/data/documentation/swiftui/<symbol>.json`). HIG pages were read through `.../tutorials/data/design/human-interface-guidelines/<page>.json`. No code was compiled for this brief.

---

## 1. How Apple's apps use Liquid Glass (iOS 26 → 27)

### Patterns across all apps
- **The tab bar floats on glass and is for navigation only.** HIG: "A tab bar floats above content… Its items rest on a Liquid Glass background". "Use a tab bar to support navigation, not to provide actions." [HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) **VERIFIED**
- **Search becomes a bottom tab.** "iOS now includes a dedicated Search tab at the bottom" ([WWDC25-356](https://developer.apple.com/videos/play/wwdc2025/356/)). The system "automatically separates the search tab from other tabs and places it at the trailing end" ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). **VERIFIED**
- **In iOS 27, Apple's own apps put the search button back inside the tab bar** "instead of floating next to it". The floating style is still supported ([MacStories iOS 27 review, p.2](https://www.macstories.net/stories/ios-and-ipados-27-review/2/)). **REPORTED** This matches the new `TabRole.prominent` (see §2).
- **Activating search morphs the bar** in Phone, News and App Store: the other tabs collapse into one leading button and the field expands at the bottom ([Apple forums 834952](https://developer.apple.com/forums/thread/834952)). **REPORTED** by a developer. The same thread says third-party apps did not get the morph in the 27.0 beta.
- **The primary action is tinted and stands alone.** It is "often as a blue checkmark on iOS". "Tinting should only be used to bring emphasis to primary elements" ([WWDC25-356](https://developer.apple.com/videos/play/wwdc2025/356/), [WWDC25-219](https://developer.apple.com/videos/play/wwdc2025/219/)). **VERIFIED**
- **Done and Close become a circular ✓ and ✕** ([MacStories iOS 26 review, p.3](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3)). **REPORTED**
- **Half sheets are inset and made of glass, and become opaque at full height.** "Partial height sheets are inset by default with a Liquid Glass background… at full height… becoming opaque" ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)). **VERIFIED**
- **The iOS 27 material.** Settings › Appearance › Liquid Glass has a slider running More Clear / Default / More Tinted. The new default is more tinted than the iOS 26 Clear setting ([MacStories 27, p.2](https://www.macstories.net/stories/ios-and-ipados-27-review/2/)). **REPORTED** Apps built for iOS 26 get this material automatically.

### App by app

| App | Tab bar | Toolbars and glass buttons | Sheets, edges, editors | Account button | Library and collections |
|---|---|---|---|---|---|
| **Music** | Home, New, Radio and Library, plus the Search tab (UNVERIFIED tab names). The bar minimises on scroll to the current tab as a small circle; the mini player slides in beside it and Search stays separate ([MacStories 26 p.3](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3)) **REPORTED**. The mini player is the `tabViewBottomAccessory`, which reads `tabViewBottomAccessoryPlacement` to switch between its inline and expanded layouts ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)) **VERIFIED**. | Top-trailing items only; content dominates. | iOS 27 artist pages have "extended artwork whose color bleeds through the entire page" ([MacStories 27 p.10](https://www.macstories.net/stories/ios-and-ipados-27-review/10/)) **REPORTED**. Now Playing works in landscape. | An avatar at the top trailing edge of Home. UNVERIFIED | Library is a list of category rows (Playlists, Artists, Albums, Songs…), each a symbol plus a label and a chevron, followed by a 2-column grid of square, rounded "Recently Added" artwork. UNVERIFIED |
| **Podcasts** | Home, New and Library, plus Search (UNVERIFIED). It has the same mini-player accessory as Music. UNVERIFIED | As Music. | — | Avatar at the top trailing edge. UNVERIFIED | Shows are a grid of square artwork. UNVERIFIED |
| **App Store** | Today, Games, Apps and Arcade, plus Search (UNVERIFIED names). The search morph is reported above. The bar is a "slimmed-down… frosted glass" bar ([MacRumors guide](https://www.macrumors.com/guide/ios-26-liquid-glass/)) **REPORTED**. | — | Full-bleed hero cards (Today). | Avatar in the large-title row at the top trailing edge. UNVERIFIED | Horizontal shelves of rounded cards. |
| **Photos** | Two tabs, Library and Collections, plus a separate Search button at the bottom right ([9to5Mac](https://9to5mac.com/2025/08/13/heres-everything-new-for-apple-photos-in-ios-26/), [MacRumors Photos](https://www.macrumors.com/guide/ios-26-photos-app/)) **REPORTED**. | In Library, a large Select button and a filter/view-options button at the top. iOS 27 adds a "Captured by Me" filter ([MacStories 27 p.11](https://www.macstories.net/stories/ios-and-ipados-27-review/11/)) **REPORTED**. Bars fade while you browse. | The grid runs edge to edge under the bars. Editor: categories in a bottom control, glass ✓/✕, and the photo as a large preview (UNVERIFIED). | A profile picture at the top of Collections ([MacStories 27 p.11](https://www.macstories.net/stories/ios-and-ipados-27-review/11/)) **REPORTED**. | Collections are carousels (Pinned, Recent Days, People & Pets, Memories, Trips, Albums). Each collapses, the order can be changed, and there are 3 sizes: default (larger top), all large or all small ([MacRumors Photos](https://www.macrumors.com/guide/ios-26-photos-app/)) **REPORTED**. Media Types and Utilities are grids ([AppleInsider](https://appleinsider.com/articles/25/06/12/photos-in-ios-26-brings-back-tabs-and-generates-spatial-photos)). |
| **Maps** | No tab bar. | Custom glass controls "float above the map content" ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)) **VERIFIED**. They are a vertical capsule group at the top trailing edge. UNVERIFIED | A persistent floating sheet. At the lowest detent it floats with a gap and fully rounded corners; at medium the gap tightens; at large it becomes a regular full sheet ([Expo teardown](https://expo.dev/blog/how-to-create-apple-maps-style-liquid-glass-sheets.md)) **REPORTED**. The map stays interactive behind it. | An avatar beside the search field in the sheet. UNVERIFIED | Places and Library live inside the sheet. |
| **Notes** | No tab bar. | Search sits "prominently… at the bottom of the screen". The formatting toolbar sits above the keyboard, can be swiped and adapts to the context: text styles, then list and indent tools when several lines are selected ([9to5Mac](https://9to5mac.com/2025/07/17/heres-everything-new-for-apple-notes-in-ios-26/)) **REPORTED**. The compose button is glass at the bottom trailing edge. UNVERIFIED | — | — | A folder list in an inset grouped style. |
| **Freeform** | None (board browser plus canvas). | Insert tools (notes, shapes, text, media, pen) sit in a centred glass toolbar group. The drawing palette floats over the canvas. UNVERIFIED: no fetched source described the iOS 26 Freeform chrome. | The canvas fills the screen and the chrome floats over it. | — | The board browser is a grid of rounded thumbnails. UNVERIFIED |
| **Files** | Recents, Shared and Browse. Search stays at the top because its filters would have to move ([MacStories 26 p.3](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3)) **REPORTED (implied)**. | — | — | — | Browse is a list of locations with tag rows. |
| **Safari** | Compact layout: a floating glass address bar that collapses to just the address on scroll ([MacRumors guide](https://www.macrumors.com/guide/ios-26-liquid-glass/)) **REPORTED**. | iOS 27: the bottom-right button opens the tabs, and Share moves behind a long press on the address bar ([MacStories 27 p.12](https://www.macstories.net/stories/ios-and-ipados-27-review/12/)) **REPORTED**. | Controls sit "on top of a system material, not directly on content" ([WWDC25-356](https://developer.apple.com/videos/play/wwdc2025/356/)) **VERIFIED**. | — | — |

Other named examples from [WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/) (**VERIFIED**):
- **Mail:** a flexible `ToolbarSpacer` separates the leading filter from a trailing group of search and compose.
- **Books:** the avatar is split from its group with `sharedBackgroundVisibility`.
- **Health:** the search-tab pattern.
- **TV:** `.onScrollDown` minimise.
- **Calendar:** a `.hard` scroll edge effect.

---

## 2. SwiftUI APIs

Availability below is copied from each page's DocC JSON. "26" means iOS, iPadOS, Mac Catalyst and macOS 26.0.

| API | Signature (abridged) | Availability | Status |
|---|---|---|---|
| `TabRole.search` (`Tab(…, role: .search)`) | `static var search: TabRole` | iOS 18, macOS 15, visionOS 2 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/tabrole/search). Put `.searchable` on the `TabView`. |
| `TabRole.prominent` | `static var prominent: TabRole` | **iOS/macOS/visionOS 27** | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/tabrole/prominent). "Only one tab can receive the prominent treatment. When there are no tabs with an explicit `.prominent` role, then a `.search` role tab may receive the prominent visual treatment by default." |
| `tabBarMinimizeBehavior(_:)` | `func tabBarMinimizeBehavior(_: TabBarMinimizeBehavior) -> some View`; values `.onScrollDown`, `.onScrollUp`, etc. | 26 (all platforms; the effect is on iPhone) | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)). It is **not deprecated** in the 27 SDK. |
| `toolbarMinimizationBehavior(_:for:)` | `func toolbarMinimizationBehavior(_: ToolbarMinimizationBehavior, for: ToolbarPlacement...)`; values `.automatic`, `.never`, `.onScrollDown`, `.onScrollUp` | **27** | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/toolbarminimizationbehavior(_:for:)). It is for the **navigation bar** (`for: .navigationBar`), and "an integrated top tab bar will also minimize". Companions: `toolbarMinimizationSafeAreaAdjustment(_:for:)` and `toolbarMinimizationRestoration(_:for:)` ([Nil Coalescing](https://nilcoalescing.com/blog/AdaptiveSwiftUIToolbarsInIOS27)). **It does not replace `tabBarMinimizeBehavior`.** No `toolbarMinimizeBehavior` symbol was found in any source, so the project note "replaces toolbarMinimizeBehavior" looks wrong. |
| `tabViewBottomAccessory(content:)` and `(isEnabled:content:)` | `func tabViewBottomAccessory<C: View>(@ContentBuilder content: () -> C)` | iOS, iPadOS and Catalyst **26 only**; no macOS | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)). The availability of the `isEnabled:` overload was not shown on the page. |
| `TabViewBottomAccessoryPlacement` | enum `.inline` / `.expanded`, read through `@Environment(\.tabViewBottomAccessoryPlacement)` | 26 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement) |
| `glassEffect(_:in:)` | `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`, which draws a capsule | 26 plus tvOS and watchOS; **visionOS not listed** | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) |
| `Glass` | `.regular`, `.clear`, `.identity`, `.tint(Color?)`, `.interactive(Bool)` | 26 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/glass) |
| `GlassEffectContainer` | `init(spacing: CGFloat?, content:)`; a higher spacing makes the shapes start blending sooner | 26 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) |
| `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)` | `glassEffectID(_ id: (some Hashable & Sendable)?, in: Namespace.ID)` | 26 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) |
| `.buttonStyle(.glass)`, `.glass(_ :Glass)`, `.glassProminent` | `static var glassProminent: GlassProminentButtonStyle`; "similar to the borderedProminent style" | 26; visionOS not listed | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent) |
| `ToolbarSpacer` | `init(_ sizing: SpacerSizing = …, placement: ToolbarItemPlacement = …)`; `.fixed` and `.flexible` | iOS and macOS 26; **no tvOS or visionOS** | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/toolbarspacer). `.flexible` is shown in WWDC25-323; the defaults are UNVERIFIED. |
| `ToolbarContent.sharedBackgroundVisibility(_:)` | `func sharedBackgroundVisibility(_: Visibility) -> some ToolbarContent`. Hiding the background "will cause the item to be placed in its own grouping." | iOS and macOS 26 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)) |
| `scrollEdgeEffectStyle(_:for:)` | `(_: ScrollEdgeEffectStyle?, for: Edge.Set)`; `.soft` (the default on iOS) and `.hard` | 26 | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)). The styles come from [WWDC25-356](https://developer.apple.com/videos/play/wwdc2025/356/). |
| `backgroundExtensionEffect()` | Mirrors and blurs the view into the safe areas, under the sidebar or inspector. "Apply this modifier with discretion." | 26, including visionOS | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()) |
| `safeAreaBar(edge:alignment:spacing:content:)` | Like `safeAreaInset`, but "extends the edge effect of any scroll views". There are horizontal and vertical-edge overloads. | 26, including visionOS | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)). The horizontal-edge page was read; the vertical-edge variant is UNVERIFIED. |
| `presentationDetents(_:)` and the glass sheet | `.presentationDetents([.height(180), .medium, .large])`. "If you've used the presentationBackground modifier… consider removing that and let the new material shine." | Detents are iOS 16+ (UNVERIFIED version); the glass look comes free with the 26 SDK | **VERIFIED** guidance from [WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/). A sheet can morph from a toolbar button with `matchedTransitionSource` + `.navigationTransition(.zoom(sourceID:in:))`. |
| `ToolbarItemPlacement.bottomBar` | `ToolbarItem(placement: .bottomBar)` | Long-standing (iOS 14, UNVERIFIED); renders as floating glass groups on the 26 SDK | Used in WWDC25-323 sample code (**VERIFIED** usage) |
| `searchToolbarBehavior(_:)` | `(_: SearchToolbarBehavior)`; `.minimized` shows the field as a button-like control when inactive (Mail's pattern) | 26, including visionOS | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)) |
| `navigationSubtitle(_:)` | `Text`, `LocalizedStringKey` and `StringProtocol` overloads | **iOS 26**; macOS 13+ | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)). It can be used on macOS 15 today. |
| `ConcentricRectangle` and `containerShape(_:)` | `ConcentricRectangle(corners:isUniform:)`, `.concentric(minimum:)`, `.fixed(_)`; `Shape.rect(corners:isUniform:)` | 26, including visionOS | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/concentricrectangle) |
| `ToolbarOverflowMenu` | `ToolbarOverflowMenu { Button… }`; its items are always in overflow. There is also `.toolbarOverflowMenu(content:)`. | **iOS, Catalyst and visionOS 27; macOS not listed** | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu) |
| `visibilityPriority(_:)` | `func visibilityPriority(_: ToolbarItemVisibilityPriority) -> some ToolbarContent`; `.low`, `.high`, `.automatic` | **iOS 27, macOS 26.1** | **VERIFIED** [doc](https://developer.apple.com/documentation/swiftui/toolbarcontent/visibilitypriority(_:)) |
| `.topBarPinnedTrailing` placement | Keeps an item at the trailing edge as the bar narrows | 27 | **REPORTED** ([Nil Coalescing](https://nilcoalescing.com/blog/AdaptiveSwiftUIToolbarsInIOS27)) |
| `reorderable()` / `reorderContainer`, generalised `swipeActions` and `swipeActionsContainer` | — | 27 | **UNVERIFIED** for signatures: the doc page could not be fetched. The names are listed on Apple's [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui) page per `docs/launch/apple-platform-2026.md`. |
| `tabViewStyle(.sidebarAdaptable)` | Turns the tab bar into a sidebar on iPad and Mac | iOS 18, macOS 15 | Already used in `MainView.swift` |

---

## 3. Version gating (deployment target iOS 18 / macOS 15)

| Group | SDK needed to compile | Runtime gate |
|---|---|---|
| `Tab(role: .search)`, `TabSection`, `.sidebarAdaptable`, `.bottomBar`, `presentationDetents`, `navigationSubtitle` on macOS | Any current SDK | None, or `#if os(macOS)` for the subtitle |
| Everything marked **26** in §2: glass, `GlassEffectContainer`, button styles, `ToolbarSpacer`, `sharedBackgroundVisibility`, `scrollEdgeEffectStyle`, `backgroundExtensionEffect`, `safeAreaBar`, `searchToolbarBehavior`, `ConcentricRectangle`, `tabBarMinimizeBehavior`, `tabViewBottomAccessory`, `navigationSubtitle` on iOS | **Xcode 26** (iOS/macOS 26 SDK) | `if #available(iOS 26, macOS 26, *)`, or a `ViewModifier` with an iOS 18 fallback. `tabViewBottomAccessory` also needs `#if os(iOS)`. |
| Free restyle with the 26 SDK: bars, tab bar, sheets, menus, Done and Close | Xcode 26 | Automatic on an OS 26 device; the iOS 18 look on iOS 18. Remove custom bar and sheet backgrounds so it shows. |
| **27 only**: `TabRole.prominent`, `toolbarMinimizationBehavior` and its companions, `ToolbarOverflowMenu`, `.topBarPinnedTrailing`, `visibilityPriority` on iOS, `reorderable`, generalised `swipeActions` | **Xcode 27 (Swift 6.4)** | **Both** a compile-time guard and a runtime check, because `#available` alone fails to *compile* on Xcode 26.x CI: `#if compiler(>=6.4)` around `if #available(iOS 27, macOS 27, *)`. That Swift 6.4 implies the 27 SDK is an assumption (Xcode 27 ships Swift 6.4 per the project facts). |
| `visibilityPriority` on macOS | Xcode 26.1+ macOS SDK | `#available(macOS 26.1, *)` |

Build-side notes:
- Building with the 27 SDK ignores `UIDesignRequiresCompatibility`.
- Apps built with the 26 SDK pick up the iOS 27 glass material automatically ([MacStories 27](https://www.macstories.net/stories/ios-and-ipados-27-review/2/)).
- With the 27 SDK, a `TabView` whose selection points at a hidden tab may crash (from `apple-platform-2026.md`, iOS 27 release notes). This matters to `MainView`, which uses `.hidden(…)` tabs.

---

## 4. HIG rules to quote

- **No glass on content.** "**Don't use Liquid Glass in the content layer.**" The exception is transient controls such as sliders and toggles. [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) **VERIFIED**
- **Use it sparingly.** "Limit these effects to the most important functional elements in your app." (same page)
- **No glass on glass.** "Always avoid glass on glass." For content on top of glass, "use fills, transparency, and vibrancy". [WWDC25-219](https://developer.apple.com/videos/play/wwdc2025/219/) **VERIFIED**
- **Regular vs clear.**
  - Regular: use it "when components have a significant amount of text, such as alerts, sidebars, or popovers."
  - Clear: "Only use clear Liquid Glass for components that appear over visually rich backgrounds". Add "a dark dimming layer of 35% opacity" over bright content. [HIG Materials]
  - "The variants should never be mixed." [WWDC25-219]
- **Tab bars.** [HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
  - The HIG gives no hard tab count: "it's generally easier to navigate among fewer tabs". It suggests a sidebar-adaptable tab bar for complex apps.
  - "A tab bar can include a dedicated search tab at the trailing end."
  - Labels: "Use single words whenever possible."
  - Accessory: "Avoid placing screen-specific actions here—a checkout button, for example, belongs with the content it supports." [WWDC25-356]
- **Toolbars.** [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
  - "Group toolbar items logically by function and frequency of use."
  - "Minimize the number of groups… aim for a maximum of three."
  - "Use the `.prominent` style for key actions such as Done or Submit… Only specify one primary action, and put it on the trailing side."
  - "Prefer simple, recognizable symbols… Keep actions with text labels separate."
  - Keep titles "under 15 characters".
  - "Don't add an overflow menu manually." On iOS 27, `ToolbarOverflowMenu` is the sanctioned route.
  - Don't group a text button with a symbol: "it could be perceived as a single button." [WWDC25-356]
- **Scroll edge.** Apply "one scroll edge effect per view". Use soft on iOS and hard mostly on macOS. Don't use it "where there aren't any floating UI elements." [WWDC25-356]
- **Accessibility.** These apply automatically to system glass [WWDC25-219]:
  - Reduce Transparency "makes Liquid Glass frostier".
  - Increase Contrast "makes elements predominantly black or white… with a contrasting border".
  - Reduce Motion "disables any elastic properties".
  - Define custom tints "with light and dark variants, and an increased contrast option for each" [Adopting Liquid Glass]. "Provide an accessibility label for every icon." Test with iOS 27's Clear↔Tinted slider too.

---

## 5. Recommendations for Cardsite

1. **iPhone tabs: four plus a search tab.** Use Home · Library · Statistics · Inbox, plus `Tab(role: .search)` with `.searchable` on the `TabView`.
   - Retire the "More" tab. Its contents move into the Library hub (item 5) and the account sheet (item 8).
   - Use one-word labels.
   - Keep `.sidebarAdaptable` for iPad and Mac. The sidebar keeps the full sectioned list (Content / Organise / Account).
   - Do not set `.prominent` on iOS 27. The search tab gets the system treatment by default (`TabRole.prominent` doc), and the tab bar must not hold a "Create" action (HIG).
2. **Minimise on scroll.** Add `.tabBarMinimizeBehavior(.onScrollDown)` behind `#available(iOS 26, *)`.
   - Skip `tabViewBottomAccessory` by default. Cardsite has no app-wide playback-like state, and the HIG forbids screen-specific actions there.
   - The only good candidate is a temporary, app-wide in-flight task such as a bulk upload or export, read through `tabViewBottomAccessoryPlacement` and shown with `isEnabled:`.
3. **Creation is a toolbar action, not a tab.**
   - Put a `+` menu (Link, Page, QR code…) top-trailing in Home and Library, as a single item.
   - In editors, the one primary action (Save/Done ✓) uses `ToolbarItem(placement: .confirmationAction)`, which the system tints. For custom chrome, use `.buttonStyle(.glassProminent)`.
   - Close is ✕ at the leading edge. Use at most 3 groups, separated with `ToolbarSpacer(.fixed)`.
4. **Account button.** Place a circular avatar top-trailing on Home and Library, split from its neighbours with `.sharedBackgroundVisibility(.hidden)` (the Books pattern), matching App Store, Music and Photos.
   - It opens an account sheet: profile, workspace, the read-only plan, sign out and delete account.
   - On iPad and Mac it stays in the sidebar header (the existing `WorkspaceSwitcher`).
   - The avatar is content-like imagery, so do not wrap it in `glassEffect`.
5. **Library hub (Music Library × Photos Collections).**
   - At the top, a Music-style list of type rows (Links, Pages, QR Codes, vCards, Events, Files, Splash, Static), each with an SF Symbol, a label, a count and a chevron.
   - Below, Photos-style collapsible shelves (Recently edited, Pinned, Top performing) of `ConcentricRectangle`/rounded thumbnails, with a view-options menu (default / all large / all small).
   - All of it sits on opaque Studio surfaces with **no glass**.
6. **Bio-page editor (Freeform-style canvas).**
   - The live page preview is the content layer, full-bleed and scrolling under the bars with the default soft edge effect.
   - Insert tools (Block, Text, Link, Image, Social, Theme) sit in a bottom floating palette built as a `GlassEffectContainer` of `.glassEffect(.regular.interactive())` buttons. Use `glassEffectID` to morph the palette into an expanded tray.
   - Block settings go in a Maps-style sheet with `[.height(…), .medium, .large]` detents, no `presentationBackground` and background interaction enabled, so the preview stays live. On iPad and Mac they use `.inspector`.
7. **QR builder (Photos-editor style).**
   - A large, centred QR preview on an opaque, high-contrast Studio surface. Never put glass over the code, because it must scan.
   - Style categories (Pattern / Colours / Logo / Frame) sit in a bottom `safeAreaBar` with a segmented picker, so the scroll edge effect applies. Their options appear in a detented sheet.
   - Top: ✕ leading and ✓ prominent trailing. Download and Share go in one fixed-spaced group.
8. **Link editor.** Use a native `Form` in a `.large` sheet on iPhone and a pushed detail on iPad and Mac.
   - Use `navigationSubtitle` (iOS 26+, macOS 13+) for the short URL.
   - On iOS 27 only (behind `#if compiler(>=6.4)`), secondary actions (Duplicate, Archive, Delete) go into `ToolbarOverflowMenu`, and Save gets `.visibilityPriority(.high)`.
9. **Edges and heroes.**
   - Remove every custom bar, tab-bar and sheet background so the system glass shows.
   - Use `backgroundExtensionEffect()` on one hero per screen (a page cover or theme banner) in the iPad/Mac detail column.
   - Keep `scrollEdgeEffectStyle` at the default; use `.hard` on Mac.
   - Use `safeAreaBar` for any custom bottom bar.
10. **Accessibility pass.** Test Reduce Transparency, Increase Contrast, Reduce Motion, VoiceOver labels on every icon button, and the iOS 27 glass slider at its extremes. Tint only the primary action with the Studio accent; keep brand colour in content, not chrome.

---

### Gaps
- No official or press source fetched for this brief describes the iOS 26/27 chrome of Freeform, Files, Podcasts or the App Store, or the Photos editor; those cells are UNVERIFIED.
- The `reorderable` and `swipeActions` signatures, and the `ToolbarSpacer` default arguments, need a check on a machine with Xcode 27.
