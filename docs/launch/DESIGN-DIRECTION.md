# Design direction: fit and finish for iOS 26/27 Liquid Glass

Research behind it: [`LIQUID-GLASS-BRIEF.md`](LIQUID-GLASS-BRIEF.md), which covers Apple's Music, Photos, Maps, Freeform and Notes, with sourced API availability. Toolchain: **CI is Xcode 26.6 (iOS 26.5 SDK, Swift 6.3)**, and the owner builds with Xcode 27.

- iOS/macOS **26** APIs must be gated with `if #available(iOS 26, macOS 26, *)`.
- iOS **27** APIs (`TabRole.prominent`, `ToolbarOverflowMenu`, `toolbarMinimizationBehavior`, `visibilityPriority`, `reorderable`) must also sit inside `#if compiler(>=6.4)`. Without it, CI doesn't compile.
- Use the app helpers in `Cardsite/Shared/LiquidGlass.swift`: `.glassButton(prominent:)`, `.minimizesTabBarOnScroll()`, `.heroBackgroundExtension()`, `.edgeBar(_:bar:)`, `.platformScrollEdge()`.
- Use the StudioKit material: `.studioGlass(...)`, `StudioGlassContainer`, `.studioGlassMorph(id:in:)`.

## The look

Studio's identity carries over unchanged:
- Bounded display type, the Editorial New serif accent word, Space Grotesk labels;
- the lime accent, used sparingly;
- opaque Studio surfaces with hairlines.

Liquid Glass is **only the functional layer**: tab bar, toolbars, floating palettes, sheets, overlays. The content layer never gets glass. Where Studio's web library uses a floating dock, an editor shell and a canvas shell, we use the native equivalents (TabView tab bar, toolbars, `GlassEffectContainer` palettes, `.inspector`, detented sheets), styled with Studio type and colour.

**Rules**
- **No glass on glass.** Glass never sits over a QR code or over body text.
- **One primary action per surface:**
  - the trailing `.confirmationAction` (✓);
  - or `.glassButton(prominent: true)` on custom chrome;
  - tinted with the Studio accent, `Color.studioAccent`/`studioAccentLine`. Nothing else is tinted.
- **Close is ✕ at the leading edge** (`.cancellationAction`). At most **three toolbar groups**. Text buttons are never grouped with symbols.
- **Remove custom bar, tab-bar and sheet backgrounds** so the system glass shows. Don't set `presentationBackground` on sheets. Don't put `toolbarBackground` on nav bars.
- **Variety without noise.** Each kind of surface gets one signature treatment:
  - Home: an editorial hero;
  - Library: shelves plus type rows;
  - editors: a canvas or stage;
  - lists: rows.
  Avoid making every screen a stack of identical cards.
- **Accessibility:**
  - Reduce Transparency: StudioKit glass already becomes opaque.
  - Increase Contrast.
  - Reduce Motion: cross-fade, no springs or morph.
  - Every icon button gets a label.
  - At AX sizes, rows stack.

## Shell: four tabs, split search

**iPhone tab bar (exactly 4 items):** **Home · Links · Library**, plus **Search** (`Tab(role: .search)`), which the system splits off as the trailing circle. This is the iOS 26 "split" pattern. On iOS 27 the system may fold search into the bar, so don't force it either way.
- Tab labels are single words.
- The tab bar minimises on scroll (`.minimizesTabBarOnScroll()`).
- No bottom accessory: Cardsite has no app-wide playback-like state.
- **No "More" tab.**
- **Library** is the hub for everything else. Its pattern is Music Library × Photos Collections:
  - type rows (Pages, QR Codes, vCards, Events, Payment Links, File Links, Static Pages, Splash Pages, then Uploads, Data, Projects, Domains, Pixels, Statistics, Activity, Workspace), each with a glyph, label, count and chevron, grouped Content / Organize / Insights;
  - above them, a "Recently edited" shelf of tiles that scrolls horizontally.
- **Account** is a circular avatar at the top trailing edge of Home and Library, in its own toolbar group (`sharedBackgroundVisibility(.hidden)` on 26). It opens the account sheet, which holds the profile, the workspace switcher, Inbox (with its badge), Preferences, Security and Sign out.
- **Inbox** is also a bell with a badge on Home.
- **Create** is a `+` menu at the top trailing edge of Home, Links and Library, listing every type. It is never a tab.
- **iPad and Mac** keep `.sidebarAdaptable`: the full sidebar in sections Overview / Content / Organize / Account. Tabs that exist only in the sidebar use `.defaultVisibility(.hidden, for: .tabBar)`. **Don't use `.hidden(_:)` tabs**: the iOS 27 SDK can crash when the selection points at a hidden tab. Search becomes the sidebar's search field.

## Editors: a premium editing experience

- **Bio page = a canvas (Freeform).** The live page preview is the content: full-bleed, centred on a device-width card on iPad and Mac.
  - A **floating glass tool palette** (`StudioGlassContainer` + glass buttons, bottom centre on iPhone and a leading rail on iPad/Mac) holds: Add Block, Blocks (the reorderable outline), Theme, Page Settings, Preview/Share.
  - Selecting a block opens its **inspector**: a detented sheet `[.height(~280), .medium, .large]` with background interaction enabled on iPhone, so the canvas stays live; `.inspector` on iPad and Mac.
  - Changes appear in the preview.
- **QR builder = a stage (Photos editor).** A large QR preview on an opaque white Studio stage at the top. It never has glass over it, so it still scans.
  - Below it, a bottom `edgeBar` with a wide segmented control: **Content · Style · Output**. Each segment shows its form.
  - ✕ at the leading edge and ✓ (prominent) at the trailing edge. Share and Download sit in one group.
- **Link and resource editors = calm forms.**
  - A hero header: address in display type, destination, state pill and figures.
  - A native grouped `Form` below.
  - `navigationSubtitle` for the short address (iOS 26 / macOS 13+).
  - Save is the one prominent action.
  - Secondary actions (Duplicate, Show Card, Delete) go in a `…` menu, or in `ToolbarOverflowMenu` on 27 behind the compiler guard.
  - vCard and event editors get a live preview card above the form.
- **Viewers.** Statistics is a dashboard hero plus a chart card. Uploads is a Photos-style grid. QR Codes is a grid of codes on white tiles.

## 15 Oct: alignment with the approved Studio 1.10 demo and Neue Glass

Sources: the Studio design system 1.10 Swift demo (`demos/swift/StudioDemo.swiftpm`) and StudioKit, both visually approved by the design owner; Neue Glass's Glass Lab (`demos/lab`) for navigation.

**Navigation (Neue Glass).** The lab defines no query interaction beyond two placements: search as its own trailing glass capsule in the bottom bar (`Tab(role: .search)`), and a magnifier in the trailing toolbar group on browsing surfaces. Its other rules: five tabs or fewer; the trailing capsule is glass for search and filled only for an action; navigation is never hidden; layout follows width, not device. Applied:
- iPhone keeps Home · Links · Library and the Search capsule. The Search tab owns its field.
- In-section list filters are now "Filter …" fields that minimise to the toolbar magnifier on iOS/visionOS 26 (`searchFilter`, `Shared/SearchFilter.swift`). `.minimize` is unavailable on macOS 26 despite the docs (CI), so the Mac keeps its toolbar field.
- The idiom check that keeps iPhone landscape on the tab bar stays deliberately: a regular-width iPhone must not get the sidebar shell.

**Studio 1.10 (demo).** One focal element per screen; quiet `StudioSectionHeader`s; numbers in a dense flush rail; neutral catalogue glyph tiles; the accent for one primary action per view; identity (not accent) avatars; 64/44 section rhythm; entrances. StudioKit takes the 1.10 spring, card padding (s5), page-head spacing and quieter neutral tone, and keeps the repo's contrast, AppKit, dataviz and accessibility improvements.

**Kept against the demo, by project rule:** editors and settings stay on the native `Form` (CLAUDE.md: native chrome), with the demo's page heads, detents and drag indicators added. The demo's compose sheet avoids `Form`.

**Seen on CI screenshots (15 Oct):** Home, Library, link detail and lists on iPhone, iPad and Mac in light and dark. Open: the Mac list selection draws the system highlight in full lime with low-contrast text; the iPhone page editor render loop (native-apple.md A31).
