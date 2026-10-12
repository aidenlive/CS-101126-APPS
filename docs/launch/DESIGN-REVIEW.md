# Cardsite Apple app: design review (source read, 12 Oct 2026)

**Method.** I read the SwiftUI source of the screens under `platform/apps/apple/Cardsite/` and rendered each one in my head on iPhone 6.9", iPad 13" landscape with the sidebar, and a 1200 pt Mac window, in light and dark, and at AX5. I measured it against PARITY-PLAN §6, CLAUDE.md and StudioKit (README plus the source of `StudioSurfaces`, `StudioComponents`, `StudioControls`, `StudioText` and `StudioViewport`).

**Verified:** each item below is checked against the source at the line given, and each StudioKit API I name exists with that signature.
**Not verified:** none of this was compiled, rendered or run. There is no toolchain in this workspace and CI is blocked. Line numbers come from the tree as read, and another agent is editing it now, so re-locate each item by symbol before fixing it.

Paths below are relative to `platform/apps/apple/Cardsite/`.

---

## P0: broken or inconsistent in ways users notice immediately

### P0-1. Two page-header systems. Only Home and Statistics follow §6.
- **Where:**
  - `Features/Home/HomeSections.swift:18` and `Features/Statistics/StatisticsScreen.swift:130` use `StudioPageHead`.
  - Every other destination has only a `.navigationTitle`. That covers Links, Pages, QR Codes, all six resource lists, Uploads, Data Records, Projects, Domains, Pixels, Workspace, Inbox, Activity Logs, Account and Preferences.
- **Problem:**
  - From Home you get a kicker, a two-tone display title and actions. Tap Projects in the sidebar and you get a bare system title over a system list.
  - §6 says "every screen uses the same page header".
  - The app has two visual languages and no rule for which screen gets which.
- **Fix:** decide on one rule and write it into PARITY-PLAN §6. I recommend this:
  - **Full-width destinations** (resource lists, Uploads, Data Records, Organise, Workspace, Inbox, Activity Logs) get `StudioPageHead` as the first list row. Keep the `.navigationTitle` for the back button and the window title.
    ```swift
    Section {
        StudioPageHead(kicker: String(localized: "Organise"), title: String(localized: "Your "),
                       accent: String(localized: "projects."),
                       description: String(localized: "Group resources into colour-coded projects."))
            .listRowInsets(EdgeInsets(top: StudioSpace.s6, leading: 0, bottom: StudioSpace.s4, trailing: 0))
            .listRowBackground(Color.clear)
    }
    ```
    Add `#if os(iOS) .navigationBarTitleDisplayMode(.inline) #endif` so the title doesn't appear twice.
  - **Split-view list columns** (Links, Pages, and QR if it becomes a split view) and **Forms** (Account, Preferences, editors) keep the native large title. Record them as a stated exception; a 360 pt column can't hold display type.

### P0-2. Lists and forms sit on three different backgrounds.
- **Where:**
  - On `Color.studioBg` with `studioSurface` rows: `Features/Resources/ResourceListScreen.swift:191,231-232`.
  - On the **system** list background, with no `.scrollContentBackground(.hidden)`:
    - `Features/Links/LinksScreen.swift:126`
    - `Features/Pages/PagesScreen.swift:227` (`.background(Color.studioBg)` at :211 is hidden behind the List)
    - `Features/Inbox/InboxScreen.swift:93`
    - `Features/Organise/ProjectsView.swift:89`
    - `Features/Library/ActivityLogsScreen.swift:119`
    - `Features/Library/DataRecordsScreen.swift:118`
  - Forms use `studioForm()`, which gives a studioBg page, but have no `editorRowBackground()`, so their rows are system-grey cells:
    - `Features/Workspace/WorkspaceScreen.swift:151`
    - `Features/Account/AccountScreen.swift:38`
    - `Features/Account/PreferencesView.swift:174`
    - `Features/Account/APITokensView.swift:245`
    - `Features/Account/TwoFactorViews.swift`
    - `Features/Account/ChangePasswordView.swift`
  - Forms that don't use `studioForm()` at all:
    - `Features/Pages/PageSettingsView.swift:157`
    - `Features/Pages/BlockInspectorView.swift:70`
    - `Features/QRCodes/QRCodeEditorView.swift:260`
- **Problem:**
  - In dark mode, the system's secondary grouped grey and `studioSurface` are visibly different colours.
  - Going Links → vCards → Projects → Account in the sidebar, the page colour and row colour change three times.
- **Fix (systemic, see S1):** every `List` and `Form` gets the same treatment:
  ```swift
  .scrollContentBackground(.hidden)
  .background(Color.studioBg)
  ```
  Every row or section gets `.listRowBackground(Color.studioSurface)` (the existing `editorRowBackground()`).
  - Rename `editorRowBackground()` to `studioRowBackground()`.
  - Fold the two background modifiers into a `studioList()` twin of `studioForm()`.
  - Apply them to every List and Form listed above.

### P0-3. The same actions have up to five names across menus, swipes and buttons.
- **Where:**

| Action | Spellings in the app |
|---|---|
| Copy | "Copy public URL" (`Links/LinksScreen.swift:193`, `Resources/ResourceListScreen.swift:242`); "Copy Address" (`Home/HomeSections.swift:633`, `Pages/PagesScreen.swift:280`, `Library/UploadsScreen.swift:200`); "Copy Link" (`Inbox/InboxScreen.swift:157`); "Copy" (swipe actions) |
| Open | "Open public link" (`LinksScreen.swift:196`, `ResourceListScreen.swift:245`); "Open in Browser" (`HomeSections.swift:639`); "Open Page" (`PagesScreen.swift:286`); "Open" (Uploads and swipe actions); "View details" (Inbox) |
| Card | "Card View" (`LinksScreen.swift:204`, `LinkDetailView.swift:280`, `ResourceEditorScaffold.swift:265`); "View Card" (`PagesScreen.swift:291`) |
| Statistics | "View statistics" (menus); "Statistics" (swipe actions); "Full statistics" (detail views) |
| On and off | "Disable link" / "Enable link" (`LinksScreen.swift:222`); "Disable" / "Enable" (`ResourceListScreen.swift:276`); "Turn Off" / "Turn On" (`PagesScreen.swift:299`) |
| State | Pills say "Live", "Off" and "Lapsing"; the toggle says "Active" and "Disabled" (`LinkDetailView.swift:214`, `ResourceEditorScaffold.swift:195`); VoiceOver hears "Active, On" |
| Delete | "Delete link…" (Links); "Delete…" (everywhere else); "Delete link" (detail view); "Delete \(kind.title)" (scaffold) |
| Edit | "Edit" (Pages menu); "Edit…" (QR Codes, Projects) |

- **Fix:** add one shared vocabulary, `enum ResourceVerb` in `Shared/` (strings only), and use it everywhere:
  - "Copy Link"
  - "Open in Browser"
  - "Show Card"
  - "Statistics"
  - "Duplicate"
  - "Turn Off" / "Turn On"
  - "Delete…"
  - "Edit…"

  For state, use "Live" and "Off" in pills, in the toggle label and in the VoiceOver value. Drop "Active", "Disabled" and "Resolving".

### P0-4. The same number appears in different formats and under different names on different screens.
- **Where:**
  - Home prints `Int.figure`, which turns 128,400 into "128K": `HomeSections.swift:117,332,343,427,560`.
  - Statistics, the link detail and every list row print `.grouped`, so the same value reads "128,400":
    - `StatisticsScreen.swift:164,171,179,185`
    - `LinkDetailView.swift:529`
    - `LinksScreen.swift:299`
    - `PagesScreen.swift:343`
    - `ResourceListScreen.swift:365`
    - `ResourceEditorScaffold.swift:211`
  - The noun changes too. The same server field is called:
    - "Total clicks" on Home.
    - "Pageviews" on Statistics. Home's "clicks" sparkline also plots `\.pageviews` (`HomeSections.swift:335`).
    - "Clicks (30 d)" in the link header, which shows `recent.pageviews` (`LinkDetailView.swift:297`).
    - "Clicks, all time" in the scaffold (`ResourceEditorScaffold.swift:216`).
    - "views" on bio-page rows, with an `eye` glyph (`PagesScreen.swift:343-345`).
- **Fix:**
  - **Display figures** (stat tiles, headline numbers, header figures) use `.figure`.
  - **Row and table figures** use `.grouped`.
  - **Nouns:**
    - Use **"Clicks"** for the per-resource total, everywhere, with `cursorarrow.click`.
    - Use **"Pageviews"** and **"Visitors"** only inside Statistics and its chart.
    - Change the link header labels to "Clicks · 30d", "Visitors · 30d" and "Clicks · all time". This matches the web's `dashboard.stat.visitors.label = "Visitors · 30d"`.

### P0-5. An error inside a card draws a second frame, with doubled padding.
- **Where:**
  - `Home/HomeScreen.swift:149-151`: `StudioCard { InlineErrorState(…) }`.
  - `Shared/StateViews.swift:85`: `InlineErrorState` builds a non-compact `StudioEmptyState`, which paints its own `studioSurface` fill, a dashed `studioBorderStrong` stroke and `s12` vertical padding.
  - The result is a dashed box inside a card, inside the card's own `s6` padding. Statistics avoids it only because `InlineErrorState` sits bare inside its `StudioCard`, which still double-frames it (`StatisticsScreen.swift:264`).
- **Fix:** in `InlineErrorState`, pass `compact: true`:
  ```swift
  StudioEmptyState(systemImage: …, title: …, message: …, compact: true) { … }
  ```
  StudioKit documents `compact` as being for "an empty state whose container already draws the frame".
  - Keep the Home call site wrapped in `StudioCard`.

---

## P1: clearly below the bar

### Layout and balance

**P1-1. Seven different content widths and no rule.**
- **Where:** the widths in use are:
  - 1120: `HomeScreen.swift:104`
  - 960: `StatisticsScreen.swift:99`, `UploadsScreen.swift:188`
  - 640: `Platform.swift:71` (default), `QRCodeDetailView.swift:56`
  - 560: `LinkEditorView.swift:96`, `PagesScreen.swift:415`, the Account sheets, `QRCodeEditorView.swift:146`
  - 520: `StateViews.swift:37,70`, `QRCodesScreen.swift:101`
  - 440: `AuthFlowView.swift:51`, `PagePreview.swift:78`
  - 420: `QRCodeDetailView.swift:19`
- **Problem:**
  - Forms have no cap at all. The link detail, the resource editors, Account and Workspace stretch across an iPad landscape detail column (about 900 pt) and a 1200 pt Mac window.
  - Lists have no cap either. Resource lists, Projects and Inbox rows run 900 pt wide, with the trailing figure and switch far from the title.
- **Fix (S2):** add `enum CardsiteMeasure` in `Shared/Platform.swift` with three widths:
  - `dashboard = 1120`
  - `reading = StudioComposition.rhythmMeasure` (680, the token)
  - `sheet = 560`

  Then:
  - Make `readableWidth(_:)` take that enum. Replace every literal above.
  - For `Form` and `List`, apply the cap through the scroll content's margins rather than the view's frame, so the scroll indicators stay at the window edge. In `studioForm()` and `studioList()`:
    ```swift
    .contentMargins(.horizontal, max(StudioSpace.s5, (width - CardsiteMeasure.reading) / 2), for: .scrollContent)
    ```
    `width` comes from `.onGeometryChange(for: CGFloat.self) { $0.size.width }`.

**P1-2. Four implementations of one row anatomy, and they disagree.**
- **Where:**

| Row | File | Glyph tile | Trailing figure |
|---|---|---|---|
| `HomeRecentRow` | `HomeSections.swift:514` | 40 pt scaled, accent-soft fill | clicks figure in `titleSm` plus a chevron |
| `LinkRow` | `LinksScreen.swift:271` | `RowGlyphTile`, 32 pt scaled | clicks in the meta line plus a switch |
| `BioPageRow` | `PagesScreen.swift:317` | `RowGlyphTile` | "views" with an `eye` glyph |
| `ResourceRow` | `ResourceListScreen.swift:325` | its own **fixed** 32 pt tile (`:334-338`), duplicating `RowGlyphTile` | — |

- **Problem:**
  - §6 asks for one anatomy: leading glyph, title over a meta line, trailing figure.
  - Only `HomeRecentRow` reflows at AX sizes.
- **Fix (S3):** extract `CardsiteResourceRow(glyph:isLive:title:subtitle:status:figure:trailing:)` in `Shared/`, with:
  - `RowGlyphTile` as the glyph.
  - Title in `.ui`, max 2 lines.
  - Subtitle in `.uiSm`, middle-truncated, for addresses.
  - A `StudioStatusPill` slot.
  - The trailing figure in `.uiSm.monospacedDigit()`, with `Label(…, systemImage: "cursorarrow.click")`.
  - An `AnyLayout` switch on `dynamicTypeSize.isAccessibilitySize` (as `HomeRecentRow:523` already does). At AX sizes it stacks and moves the switch under the text.

  Then:
  - Make the four rows thin wrappers around it.
  - Delete `ResourceRow`'s private tile.

**P1-3. Loading states aren't designed, and they differ from screen to screen.**
- **Where:**
  - A bare `ProgressView` for every list that goes through `ListStateView` (Links, Pages, resource lists, Organise, Library, Inbox): `Shared/StateViews.swift:22-26`. Also `ResourceListScreen.swift:38`, `StatisticsScreen.swift:51`, `LinkDetailView.swift:39` and `WorkspaceScreen.swift:134`.
  - QR Codes has a real skeleton grid (`QRCodesScreen.swift:74-86`) and Home a redacted layout. Home also stacks a spinner under its skeleton (`HomeScreen.swift:145`).
- **Problem:** §6 requires a skeleton loading state, and as it stands the lists flash a spinner on an empty page.
- **Fix:**
  - Give `ListStateView` a `placeholder: () -> some View` parameter. Have it render 6 redacted rows, built with the S3 row and sample data, under `.redacted(reason: .placeholder)` and `.loadingAccessibility(true)`. That modifier already exists at `StatisticsScreen.swift:427`; move it to `Shared/`.
  - Remove the extra `ProgressView` at `HomeScreen.swift:145`.

**P1-4. The Uploads filter bar doesn't line up with the content.**
- **Where:** `Library/UploadsScreen.swift:113-140`. The segmented picker sits in a `safeAreaInset` with `.padding(.horizontal, StudioSpace.s4)` and is **not** width-capped. The gallery below is capped at 960 and centred (`:188`).
- **Problem:** on a Mac at 1200 pt, the picker hugs the left edge about 100 pt to the left of the grid. The bar's opaque `studioBg` strip also fights the toolbar's material.
- **Fix:** move the picker into the toolbar, as Inbox does:
  ```swift
  ToolbarItem(placement: .principal) { Picker(…).pickerStyle(.segmented).fixedSize() }
  ```
  Then:
  - Move "x MB used" into the page head description, or to a `.status` toolbar item on Mac.
  - Delete the `safeAreaInset`.

**P1-5. Sheet sizing is ad hoc: about 25 different Mac minimums and no iPad sizing.**
- **Where:** about 25 `.frame(minWidth: 400…720, minHeight: 200…620)` calls (see `grep frame(minWidth`), including:
  - `LinkEditorView.swift:125`
  - `PagesScreen.swift:444`
  - `ResourceListScreen.swift:127,140`
  - `MainView.swift:146`
  - `Organise/OrganiseShared.swift:140`
  - every Account sheet

  On iPad, only the QR editor sets `.presentationSizing(.page)`. Statistics sheets (`LinksScreen.swift:89`, `ResourceListScreen.swift:130`, `ResourceEditorScaffold.swift:109`) open form-sized, at about 540 pt, which squeezes the chart and tiles.
- **Fix (S4):** add one modifier, `cardsiteSheet(_ size: CardsiteSheetSize)`, where `CardsiteSheetSize` is `.form` or `.page`:
  - On iOS: `.presentationSizing(size == .page ? .page : .form)` (available from iOS 18).
  - On macOS: `.frame(minWidth: size == .page ? 720 : 480, idealWidth: size == .page ? 900 : 560, minHeight: size == .page ? 600 : 420)`.

  Use `.page` for Statistics, the QR editor and the resource editors. Use `.form` for everything else. Delete `organiseSheetFrame()`.

**P1-6. Link detail and resource headers mix two button systems.**
- **Where:** `LinkDetailView.swift:267-283` and `ResourceEditorScaffold.swift:252-268`. Copy is a `StudioButton(.primary)` pill, while Open and Card View are system `.buttonStyle(.bordered)` rounded rectangles in a different height, radius and type.
- **Fix:** keep everything in one system.
  ```swift
  StudioButton(String(localized: "Open in Browser"), systemImage: "safari", variant: .outline) { openURL(url) }
  StudioButton(String(localized: "Show Card"), systemImage: "rectangle.portrait.on.rectangle.portrait", variant: .ghost) { openURL(card) }
  ```
  Use `@Environment(\.openURL)`. Also see S5: these two headers are copy-pasted and should be one view.

**P1-7. Form section headers come in two styles.**
- **Where:**
  - Studio `.label` through `EditorSectionHeader`: link detail, resource editors, Organise editors.
  - Native `Section("…")` / `Text("…")` headers:
    - `AccountScreen.swift:42,62`
    - `WorkspaceScreen.swift:236,249`
    - `PreferencesView.swift`
    - `QRCodeEditorView.swift` ("Output")
    - `PageSettingsView.swift`
    - `BlockLibrarySheet.swift:79`
- **Problem:** on iOS 26 the two render at different size, weight, tracking and case.
- **Fix:** use `EditorSectionHeader` (renamed `StudioFormHeader`) everywhere, or the native header everywhere. One or the other.
  - I recommend the **native** header. It is what the HIG expects for a grouped `Form`, and it keeps Dynamic Type metrics.
  - Under that option, drop `EditorSectionHeader` and its uppercase `.label` style.

### Native feel

**P1-8. Statistics uses a custom segmented control.**
- **Where:** `StatisticsScreen.swift:135-141`, `StudioSegmented`. Inbox (`InboxScreen.swift:59`), Uploads (`:123`), the QR editor (`:245`) and the page editor (`:467`) all use `Picker(.segmented)`.
- **Fix:**
  ```swift
  Picker(String(localized: "Date range"), selection: $model.range) {
      ForEach(StatisticsModel.Range.allCases, id: \.self) { Text($0.shortTitle).tag($0).accessibilityLabel(Text($0.accessibilityTitle)) }
  }
  .pickerStyle(.segmented)
  .fixedSize()
  ```

**P1-9. Each screen reports errors in its own way.**
- **Where:**
  - Alerts with different titles:
    - "Couldn’t delete" (curly apostrophe) and "Couldn't delete" (straight)
    - "Failed to update link status"
    - "Couldn't do that"
    - "Couldn't complete that"
    - "Something went wrong"
    - "Couldn't update the inbox"
  - Pages alone uses toasts (`PagesScreen.swift:23,164`).
  - Retry is done four different ways: a button that is itself the error (`AccountScreen.swift:215`), a "Tap to try again" row (`WorkspaceScreen.swift:279`, `AccountScreen.swift:173`), `InlineErrorState`, and "Pull to refresh to try again" (`LinkDetailView.swift:358`).
- **Fix:**
  - Use one alert title pattern: "Couldn’t \(verb)", with a curly apostrophe, sentence case and no "Failed to".
  - Show success feedback through `StudioToastCenter` app-wide, not only in Pages. Inject it once in `MainView` with `.studioToasts(_:)`.
  - Every inline load failure inside a Form becomes a row with the message plus a trailing `Button("Try Again")`.

**P1-10. The refresh-error banner reinvents a StudioKit API, with a tap target that is too small.**
- **Where:** `Shared/StateViews.swift:105-119`. An `xmark` with `.padding(StudioSpace.s2)` gives about 30 pt, below `StudioLayout.tapTarget` (44).
- **Fix:** replace the whole view body with:
  ```swift
  StudioBanner(lead: String(localized: "Not up to date."), message: error.localizedDescription, tone: .warning, onDismiss: dismiss)
  ```
  StudioKit's own dismiss button is 32 pt with a press style. Ask StudioKit to raise it to `StudioLayout.tapTarget`.

### Accessibility

**P1-11. List rows don't reflow at AX sizes, so addresses truncate to a few characters.**
- **Where:**
  - `LinksScreen.swift:278-323`: an `HStack` of the tile, the address with `.lineLimit(1)` (`:286`) and a switch.
  - `PagesScreen.swift:322`.
  - `ResourceListScreen.swift:333`.
  - `DataRecordsScreen.swift:207-217` (`.lineLimit(1)`).
- **Problem:** at AX5 on iPhone the address gets about 120 pt next to a switch.
- **Fix:** covered by S3. At `isAccessibilitySize`, switch to a `VStackLayout`, set `lineLimit(3)`, and put the switch on its own line below the text.

**P1-12. Display-size user content is clipped at AX5.**
- **Where:**
  - `QRCodeDetailView.swift:28-33`: the code name in `.display`, `.lineLimit(3)`, `.minimumScaleFactor(0.6)`.
  - `HomeSections.swift:386-391`: the top performer's address in `.title`, `.lineLimit(1)`, `.minimumScaleFactor(0.6)`, truncated at the **tail**, so the slug, the part that matters, is the bit cut off.
  - `LinkDetailView.swift:188-193`: `.lineLimit(3)` on the address.
- **Fix:**
  - QR name: drop the `lineLimit`. Use `.studioText(dynamicTypeSize.isAccessibilitySize ? .title : .display)`.
  - Top performer: pass `lineLimit(2)` and `.truncationMode(.middle)` for this card. Add a `valueLineLimit` parameter to `HomeStatCard`.
  - Link detail address: remove `lineLimit(3)`; `.fixedSize(horizontal: false, vertical: true)` is enough.

**P1-13. Grid minimums don't scale with Dynamic Type.**
- **Where:** `QRCodesScreen.swift:140` (`GridItem(.adaptive(minimum: 156, maximum: 260))`) and `UploadsScreen.swift:152` (`minimum: StudioSpace.s16 * 2`).
- **Problem:** at AX5 the iPhone still shows two 156 pt columns of cards whose titles are 40 pt or more.
- **Fix:** do what Statistics does (`@ScaledMetric(relativeTo: .body) private var tileMin: CGFloat = 156`). Also drop `maximum:` when `isAccessibilitySize`.

**P1-14. The QR card's overflow button is too small and covers the artwork.**
- **Where:** `QRCodesScreen.swift:157-163`. The frame is `StudioSpace.s10` (40 pt).
- **Fix:**
  ```swift
  .frame(minWidth: StudioLayout.tapTarget, minHeight: StudioLayout.tapTarget)
  ```
  On iOS, hide it unless `horizontalSizeClass == .regular`; the context menu already mirrors it. On Mac it should appear on hover.

**P1-15. `StudioPageHead` doesn't stack at AX sizes on iPad or Mac.**
- **Where:** in StudioKit, `StudioSurfaces.swift:79-91` stacks only when `viewport == .compact`. Home puts three headline figures in its actions slot (`HomeSections.swift:24`), so at AX5 on iPad the greeting wraps one word per line beside the figures.
- **Fix:** this is upstream in StudioKit. Make the condition `viewport == .compact || dynamicTypeSize.isAccessibilitySize`. Until then, in `HomeGreeting`, pass the figures through `description:`, or render them below the head when `isAccessibilitySize`.

### Typography and copy

**P1-16. The uppercase `.meta` style mangles proper nouns in pills.**
- **Where:** `StudioStatusPill` renders `.meta`, which is uppercase.
  - `QRCodesScreen.swift:237`: `StudioStatusPill(typeLabel)` turns "WiFi" into "WIFI" and "vCard" into "VCARD".
  - `ResourceEditorScaffold.swift:239`: `StudioStatusPill(kind.title)` gives "VCARD" and "PAYMENT LINK".
  - Using a status pill for a *type* label is also wrong semantically.
- **Fix:** render the type as `Text(typeLabel).studioText(.uiSm).foregroundStyle(Color.studioText3)` next to its glyph. Keep pills for state only: Live, Off, Lapsing, Saved, and the role.

**P1-17. Title case and sentence case are mixed on the same surfaces.**
- **Examples:**
  - The sign-in card has the heading "Sign in" and the button "Sign In" (`AuthFlowView.swift:71,81`).
  - In one Inbox menu: "Mark as read", "View details", "Copy Link" (`InboxScreen.swift:145-157`).
  - Navigation titles:
    - "Create pixel", "Edit pixel" (`PixelsView.swift:325`)
    - "Add domain" (`DomainEditor.swift:320`)
    - "Create project" (`ProjectsView.swift:276`)
    - against "Create Workspace", "Add Member", "New Bio Page", "Change Password", "Edit QR Code"
  - Buttons:
    - "Full statistics", "Create QR code", "Delete link" (`LinkDetailView.swift:232,238,489`)
    - against "Edit Name", "Change Password…", "Sign Out"
  - "Link statistics" against "Activity Logs".
- **Fix:** adopt the HIG rule and write it in `docs/launch/native-apple.md`:
  - **Title case** for control labels: buttons, menu items, toolbar items, navigation titles, sidebar and tab titles, alert buttons.
  - **Sentence case** for everything that reads as prose: headings inside content, section headers, empty-state titles, help text, alert messages.

  Under that rule, correct each string above. The nouns still match the web.

**P1-18. US and UK spelling are mixed, and the web uses US.**
- **Where:**
  - "Organise" is the sidebar group (`Destinations.swift:80`).
  - "organize your links" (`ProjectsView.swift:83`).
  - "color-coded" (`ProjectsView.swift:123`).
  - "colours", "Background colour" and "Text colour" (`PageSettingsView.swift:34,324,338-345`).
  - "Edits the name and colour" (`ProjectsView.swift:103`).
  - The web locale has no "organis*" and uses "color" 31 times to "colour" once.
- **Fix:** use US spelling throughout to match `en.json`: "Organize", "color". Keep the Swift type and folder names (`Organise/`) as they are; only user-visible strings change.

**P1-19. Destructive confirmations say different things about the same delete.**
- **Where:**
  - The Links list says: "Anyone who opens or scans this address will get a not-found page. This can't be undone." (`LinksScreen.swift:112`)
  - The link detail says: "Its address stops resolving immediately. This cannot be undone." (`LinkDetailView.swift:112`)
  - The dialog title is "Delete this link?" in the list and "Delete /slug?" in the detail.
  - Projects: "Are you sure you want to delete this project? …" (`ProjectsView.swift:146`). It repeats the title as a question.
- **Fix:**
  - Take one consequence string per kind from `ResourceKind.deleteConsequence`, and add a matching one for short links.
  - Use the list wording in both places, with a curly "can’t".
  - Remove "Are you sure…".

---

## P2: polish

1. **Statistics accent words lack the full stop that Home's have.** At `StatisticsScreen.swift:132-133`, "The whole library" and "The whole story" have no period, while Home's accents are "new.", "resources." and "left off.". Add the period. Also change "library" to "workspace", which is the noun the rest of the app uses.
2. **Empty-state copy differs across screens:**
   - "Not enough data for this period." (`StatisticsScreen.swift:224`) and "No data for the selected period." (`:266`): pick one.
   - "No inbox notifications yet." (`InboxScreen.swift:49`) is the only empty title that ends with a full stop. Drop it.
3. **Two-tone accents are meant to be one word, per the StudioKit doc.** Two have more:
   - `AuthFlowView.swift:22`: "is a link." Restructure as `("Every resource is a ", accent: "link.")`.
   - `HomeSections.swift:141,482`: "left off.". Fine as the web has it, but note it as an exception.
4. **The Home kicker isn't localized.** `HomeSections.swift:32` builds `"Cardsite · \(weekday) · \(date)"` as a plain string. Use `String(localized: "Cardsite · \(weekday) · \(date)")`, or `Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()` in one call.
5. **Home's sparklines use accent ink instead of the chart palette.** At `HomeSections.swift:335,346`, StudioKit says charts use `studioViz*`. Use `Color.studioViz1` for clicks and `Color.studioViz2` for visitors, matching `TrafficChart.swift:28,40`, so the two charts agree. The sparkline is also `accessibilityHidden`. Add `.accessibilityValue(Text(trendSummary))`, for example "Up 12% on the previous 15 days", so the trend isn't visual-only.
6. **The breakdown header doesn't line up with its columns.** At `StatisticsScreen.swift:340-345`, an `HStack` with `Spacer` puts "Views" and "Share" wherever their widths fall. Use a `Grid` with `GridRow` for the header and each bar, `gridColumnAlignment(.trailing)` on the figures, and `.monospacedDigit()`.
7. **Tabular figures in the custom faces are unverified.** `.monospacedDigit()` only works if the font has `tnum`. Confirm that the Space Grotesk and Certia files carry it. If they don't, the stat tiles jitter under `.contentTransition(.numericText())`. This is a CI snapshot check.
8. **Untuned animations ignore Reduce Motion.** These use `.animation(.default, …)`:
   - `AuthFlowView.swift:55` (animates the card height as forms swap)
   - `RootView.swift:25-26`

   Use `StudioAnimation.resolve(StudioAnimation.standard, reduceMotion: reduceMotion) ?? StudioAnimation.base`, or simply `StudioAnimation.base` (a 0.18 s ease, effectively a cross-fade).
9. **Split-view placeholders use the system look.** `ContentUnavailableView` in Links (`:77`) and Pages (`:55,67`) looks different from `StudioEmptyState`. Either is fine, but use one. I suggest `StudioEmptyState(systemImage:title:message:compact: true) { EmptyView() }` on `studioBg`, so empty detail panes look like empty lists.
10. **Swipe actions don't mirror the menus.**
    - Bio pages have only Delete and Copy (`PagesScreen.swift:242-255`), but their menu has Duplicate and Turn Off. Add Duplicate on the trailing edge, as Links has.
    - The leading Copy swipe copies `""` when there's no URL (`:249`). Guard it as Links does.
11. **Home's recents rows have a context menu but no swipe actions or detail actions.** At `HomeSections.swift:501`, add Statistics and Delete… to `ResourceActions` so a long press on Home offers the same actions as the list.
12. **The palette prompt is shorter than the search prompt.** "Search pages, actions…" (`CommandPalette.swift:114`) against "Search pages, actions and links" (`HomeScreen.swift:27`). Use the longer one in both.
13. **More rows are undersized.** At `MainView.swift:256`, `.studioText(.ui)` (14 pt) on native `List` labels makes More's rows smaller than the system's 17 pt rows, and smaller than the sidebar, which uses system type. Remove the modifier and let `List` set the type.
14. **The QR detail has two Edit buttons.** One is in the toolbar (`QRCodeDetailView.swift:65`) and one in the body (`:50`). Keep the toolbar one. Make the body Delete a Form-style danger zone, to match link and resource details, or keep both buttons and drop the toolbar one. Not both.
15. **Large Mac windows deserve tables.** Activity Logs and Data Records on a 1200 pt Mac are single-column rows. Use `Table` on macOS (`#if os(macOS)`), or `StudioTable(caption:columns:rows:)`, which already exists, with date, event and device columns.
16. **Dates relative to now don't update.** `Text(date.formatted(.relative(presentation: .named)))` (`InboxScreen.swift:211`, `WorkspaceScreen.swift:308`) is static. Use `Text(date, style: .relative)` or `Text(date, format: .relative(presentation: .named))` inside a `TimelineView(.periodic(from: .now, by: 60))`.
17. **Card padding varies.** Inside flush cards it is `s4` for QR cards (`QRCodesScreen.swift:245`) and `s5` horizontally for Home recents (`HomeSections.swift:574`). The grid gutter is `s5` on QR Codes (`:81,133`) and `viewport.contentPadding` on Home and Statistics. Use `viewport.contentPadding` for page gutters and `StudioSpace.s5` inside flush cards everywhere.
18. **The literal-width lint will fail.** §6's CI lint is about `.padding(<number>)`, but `.frame(maxWidth: 520/560/440/420)` and `minWidth: 156` are the same kind of literal. S2 removes them.

---

## Systemic fixes: change once, in a shared component

| # | Change | Where | Resolves |
|---|---|---|---|
| **S1** | `studioList()` and `studioForm()` both apply `.scrollContentBackground(.hidden)`, `.background(Color.studioBg)` and the measure cap. Rename `editorRowBackground()` to `studioRowBackground()` and use it on every section and row. Pick one section-header style. | `Features/ResourceEditor/EditorFields.swift:130-163`; move to `Shared/` | P0-2, P1-1, P1-7 |
| **S2** | `enum CardsiteMeasure { dashboard 1120, reading StudioComposition.rhythmMeasure, sheet 560 }`. `readableWidth(_:)` takes it. Ask StudioKit for a `StudioLayout.contentMax` token so the two platforms share it. | `Shared/Platform.swift:71` | P1-1, P2-18 |
| **S3** | `CardsiteResourceRow` with one anatomy (`RowGlyphTile`, title, middle-truncated subtitle, status pill, trailing figure or switch) and an AX `AnyLayout` reflow. | new, `Shared/` | P1-2, P1-11, P0-4 (figure format) |
| **S4** | `cardsiteSheet(.form / .page)`, using `presentationSizing` on iOS and min/ideal frames on macOS. | new, `Shared/` | P1-5 |
| **S5** | `ResourceHeaderSection`: status pill, name, address, Copy / Open in Browser / Show Card as `StudioButton`s, Live/Off toggle, figures, Statistics. Shared by `LinkDetailView` and `ResourceEditorScaffold`, which today duplicate about 90 lines with drift. | `Features/Resources/ResourceEditorScaffold.swift:157-235` and `Features/Links/LinkDetailView.swift:178-300` | P1-6, P0-3, P0-4 |
| **S6** | `ResourceVerb` and `ResourceState` string tables, one vocabulary for menus, swipes and pills. One `ResourceContextMenu(resource:actions:)` builds both the context menu and the swipe actions from the same list, so they can't drift apart. | new, `Shared/` | P0-3, P2-10, P2-11 |
| **S7** | `ListStateView` gains a skeleton placeholder. `InlineErrorState` passes `compact: true`. `RefreshErrorBanner` becomes `StudioBanner(…, onDismiss:)`. One toast centre at the shell. | `Shared/StateViews.swift` | P0-5, P1-3, P1-9, P1-10 |
| **S8** | Upstream in StudioKit: `StudioPageHead` stacks at `isAccessibilitySize`; the `StudioBanner` dismiss target becomes `StudioLayout.tapTarget`. Also review `StudioListRow`: its fixed 64 pt tile and uppercase `.meta` caption make it unusable for addresses, which is why the app doesn't use it. | `platform/studio/packages/swift/Sources/StudioKit/StudioSurfaces.swift:79`, `StudioComponents.swift:369` | P1-15, P1-10 |
| **S9** | A copy style note in `docs/launch/native-apple.md`: title case for controls and sentence case for prose; US spelling; the noun list ("short link", "bio page", "QR code", "clicks", "Live"/"Off"); curly apostrophes; no "Failed to" or "Are you sure". | docs | P1-17, P1-18, P1-19, P2-1…3 |

**Checked and fine:**
- No sales language anywhere. The plan is read-only (`AccountScreen.swift:208-224`), and the locked-block copy (`BlockLibrarySheet.swift:56-58`) states the fact without an offer.
- Liquid Glass appears only on the ⌘K palette (`CommandPalette.swift:81`), which is chrome.
- Native chrome throughout: `TabView(.sidebarAdaptable)`, `NavigationSplitView`, toolbars and system sheets. No custom tab bar or back buttons.
- `TrafficChart` has a proper `AXChartDescriptor` and a non-colour legend (solid against dashed).
- Breakdown bars reflow at AX sizes.
- The `.meta`, `.label` and `.kicker` styles are not used on emails, URLs or sentences. The only uppercase-on-content problems are the pills in P1-16.

---

## Resolution (design-polish pass, 12 Oct 2026)

**Verified:** `tools/check.sh` (tree-sitter syntax) reports 0 errors on `Cardsite/` and on `StudioKit/`; `scripts/lint-design.sh` is clean; every `.accessibilityIdentifier` the UI tests use is still in place (`link.detail.enabled` now comes from `ResourceHeaderSection`'s toggle). **Not verified:** nothing was compiled, rendered or run. There is no Swift toolchain here, so every "Done" below means "changed in source", and the screenshots in CI are the real check.

### Shared pieces built (systemic fixes)

| # | What exists now | Where |
|---|---|---|
| S1 | `studioList(measure:)` and `studioForm(measure:)` (Studio page, hidden system background, measure cap through `contentMargins(.horizontal, …, for: .scrollContent)`); `studioRowBackground()` (and `studioRowBackground(isSelected:)` for split-view columns, whose custom background would otherwise hide the selection); `studioClearRow()`; `ListPageHead` + `inlineNavigationTitle()`. `editorRowBackground()` stays as a forwarding alias for in-flight branches. One header style: `EditorSectionHeader` now renders the native grouped-form header. | `Shared/ListStyle.swift`, `Features/ResourceEditor/EditorFields.swift` |
| S2 | `CardsiteMeasure` (`dashboard` 1120, `reading` = `StudioComposition.rhythmMeasure`, `sheet` 560, plus `narrow` 440 for the sign-in card, the phone-sized page preview and QR artwork); `readableWidth(_:)` takes it. No width literals remain in `Cardsite/` except the Siri snippet's artwork (`Intents/ShowQRCodeIntent.swift`). | `Shared/Platform.swift` |
| S3 | `CardsiteResourceRow(systemImage:isLive:title:subtitle:detail:state:clicks:trailing:)` with an `AnyLayout` AX reflow; `ClicksFigure`; `LiveSwitch`. `LinkRow`, `BioPageRow`, `ResourceRow`, `HomeRecentRow` and `DataRecordRow` are thin wrappers; `ResourceRow`'s private tile is gone. | `Shared/CardsiteResourceRow.swift` |
| S4 | `cardsiteSheet(.form / .page)`: `presentationSizing` on iOS, min/ideal frames on macOS. Every sheet uses it (the Mac Settings window keeps its own frame); `organiseSheetFrame()` is deleted. | `Shared/ListStyle.swift` |
| S5 | `ResourceHeaderSection` (state pill + Saved, title, address, Copy Link / Open in Browser / Show Card as `StudioButton`s plus the type's actions, the Live switch, display figures, caller rows, release-window banner), with `ResourceLiveToggle` and `ResourceFigure`. `LinkDetailView` and `ResourceEditorScaffold` both use it; their copies are deleted. | `Shared/ResourceHeaderSection.swift` |
| S6 | `ResourceVerb` (titles and glyphs), `ResourceState` (Live / Off / Lapsing, with its pill), `ResourceActionSet`, `ResourceMenuItems` and `.resourceSwipeActions(_:)`: menus and swipes are built from one action set, so they can't drift. | `Shared/ResourceVerb.swift` |
| S7 | `ListStateView(…, skeleton:)` renders `ListSkeletonView` (six redacted rows in the real anatomy, one "Loading" for VoiceOver); `loadingAccessibility(_:)` moved to `Shared/`; `InlineErrorState` is compact; `RefreshErrorBanner` is `StudioBanner(…, onDismiss:)`; `FormRetryRow` (message + Try Again) for load failures inside Forms; `SplitPlaceholder`; one `StudioToastCenter` injected by `MainView` as `\.toasts`. | `Shared/StateViews.swift`, `App/MainView.swift` |
| S8 | StudioKit, additive only: `StudioPageHead` stacks when `dynamicTypeSize.isAccessibilitySize`; `StudioBanner`'s dismiss target is `StudioLayout.tapTarget`; new `StudioButtonStyle(_ variant:)` gives `Link`, `ShareLink` and `Menu` the `StudioButton` look. **Deferred:** the `StudioListRow` review (fixed 64 pt tile, uppercase caption); the app uses `CardsiteResourceRow` instead. | `StudioSurfaces.swift`, `StudioComponents.swift` |
| S9 | The copy rule is recorded in PARITY-PLAN §6 (with the header and measure rules). **Not done:** the same note in `docs/launch/native-apple.md`, which this agent doesn't own; the lead can copy the §6 "Copy" bullet across. | `docs/launch/PARITY-PLAN.md` |

### P0

| Item | Status | Notes |
|---|---|---|
| P0-1 Page headers | Done | Rule in PARITY-PLAN §6. `ListPageHead` on the six resource lists, Projects, Domains, Pixels, Inbox, Activity Logs, Data Records and Workspace; Uploads uses `StudioPageHead` at the top of its gallery. Kickers and descriptions are the web's where `en.json` has them. Links, Pages and Forms keep native titles. |
| P0-2 Three backgrounds | Done | Every listed List and Form is on `studioList()` / `studioForm()` with Studio rows, plus More, API Tokens, Page Settings, the block inspector and the QR builder. Picker sheets (timezone, targeting values, QR type) and the bio page block list keep system rows: they are pickers or a selection column. |
| P0-3 Action names | Done | `ResourceVerb` everywhere: Links, Pages, resource lists, Home recents, the page editor's share menu, Uploads, Inbox, Organize, the detail headers. State words are Live / Off; "Active", "Disabled" and "Resolving" are gone (the toggle caption for Live is "Anyone with the address can open it."). |
| P0-4 Numbers and nouns | Done | Rows print `.grouped` through `ClicksFigure`; tiles and headers print `.figure` (Statistics tiles now abbreviate too). "Clicks" with `cursorarrow.click` on every row (bio pages no longer say "views"); the link header reads "Clicks · 30d", "Visitors · 30d", "Clicks · all time". "Total clicks" stays on Home: it is the web's `dashboard.stat.totalClicks.label`. |
| P0-5 Doubled error frame | Done | `InlineErrorState` passes `compact: true`. |

### P1

| Item | Status | Notes |
|---|---|---|
| P1-1 Content widths | Done | See S1/S2. |
| P1-2 Row anatomy | Done | See S3. Home's row now uses `RowGlyphTile` (the 40 pt accent-soft tile is gone) and a `.grouped` figure. |
| P1-3 Loading states | Done | Skeletons for every `ListStateView` list, the resource list before its model exists, and Workspace; Home's extra spinner is gone. Statistics, the link detail and the resource composer showed a spinner for the one frame before `.task` builds their model; they now show the empty page instead. |
| P1-4 Uploads filter bar | Done | Picker in the toolbar's principal slot; storage in the page head's description; the `safeAreaInset` is deleted. |
| P1-5 Sheet sizing | Done | See S4. Statistics, the QR builder and the resource editors are `.page`. |
| P1-6 Two button systems | Done | See S5; vCard, event and file-link header actions use `StudioButtonStyle(.outline)`. |
| P1-7 Section headers | Done | Native header everywhere (`EditorSectionHeader` renders it). |
| P1-8 Custom segmented control | Done | `Picker(.segmented)` with per-segment accessibility labels. |
| P1-9 Error reporting | Done | Alert titles are "Couldn’t …" (Links, Pages, resources, Organize, Uploads, Inbox, Workspace, Data Records, QR); Pages' toasts and copy confirmations go through the shell's toast centre; Form load failures use `FormRetryRow` (link pickers, Account plan and 2FA, Workspace activity, QR types). The new-resource address footer still says the domains didn't load, without a retry row. |
| P1-10 Refresh banner | Done | StudioKit's dismissible banner, now with a 44 pt target. |
| P1-11 Rows at AX sizes | Done | Through S3 (Links, Pages, resource lists, Data Records, Home recents). |
| P1-12 Display text clipped | Done | QR name drops to `.title` at AX sizes with no line limit; the top performer wraps to 2 lines with middle truncation (`valueLineLimit`); the link header address has no line limit. |
| P1-13 Grid minimums | Done | `@ScaledMetric` minimums on QR Codes and Uploads; QR drops `maximum:` at AX sizes. |
| P1-14 QR overflow button | Done | 44 pt target; shown on hover on Mac and in regular width on iPad, hidden on iPhone (the context menu has the same items). |
| P1-15 Page head at AX | Done | Upstream in StudioKit (S8). |
| P1-16 Uppercase pills | Done | Type labels are plain `.uiSm` text on QR cards, the QR detail (was a kicker), the resource header and Data Records. |
| P1-17 Case | Done | Navigation titles and controls are title case ("Create Project", "Edit Pixel", "Add Domain", "Create Event", "Link Statistics", "Mark as Read", "Forgot Password?", "Back to Sign In", "Create an Account"…). The sign-in heading "Sign in" stays: it is a heading inside content, so sentence case is right under the rule. Form toggle labels stay sentence case, as Settings-style row text. |
| P1-18 Spelling | Done | "Organize", "color", "behavior", "center", "canceled" in every user-visible string; Swift names and the `Organise/` folder are unchanged. The search keywords keep "organise" alongside "organize" so either finds Projects. |
| P1-19 Delete copy | Done | One consequence per kind (`ResourceKind.deleteConsequence`, plus `shortLinkDeleteConsequence`), the list's wording, a curly "can’t"; confirm buttons say "Delete"; no "Are you sure". |

### P2

| # | Status | Notes |
|---|---|---|
| 1 | Done | "The whole workspace." / "The whole story." |
| 2 | Done | "No data for this period" in both places; the Inbox (and API tokens) empty titles lost their full stop. |
| 3 | Done | Sign-in title is "Every resource is a " + "link."; Home's "left off." kept as the web's exception. |
| 4 | Done | Kicker built with `String(localized:)`. |
| 5 | Done | `studioViz1` / `studioViz2` with the Statistics chart's fill; the sparkline speaks a trend ("Up 12% on the previous 15 days"). |
| 6 | Done | Header and bars share scaled figure columns; the heading is "Pageviews" (inside Statistics). The bars keep their own background-bar layout rather than moving to `Grid`. |
| 7 | Deferred | Needs a CI snapshot of the font tables. |
| 8 | Done | `StudioAnimation.base` in the auth flow and `RootView`. |
| 9 | Done | `SplitPlaceholder` in Links and Pages. |
| 10 | Done | Bio pages get the full swipe set, including Duplicate; copy is only offered when there is an address. |
| 11 | Partly done | Home's context menu adds Show Card and Statistics (in a `.page` sheet). Delete is left out: Home has no delete flow for arbitrary types, and adding one means a per-type model call. |
| 12 | Done | The palette prompt is "Search pages, actions and links". |
| 13 | Done | |
| 14 | Done | Edit stays in the toolbar; the body keeps Delete only. |
| 15 | Deferred | Mac `Table`s for Activity Logs and Data Records need column design and a sort model; the rows are the shared anatomy for now. |
| 16 | Done | `RelativeTimeText` (a minute `TimelineView`) in Inbox and Workspace activity. |
| 17 | Done | QR cards pad `s5`; QR and Uploads gutters are `viewport.contentPadding`. |
| 18 | Done | See S2. |

**Counts:** systemic 9 of 9 built (S8 partly: `StudioListRow` deferred; S9 partly: the `native-apple.md` copy is for the lead). P0 5/5 done. P1 19/19 done. P2 15 done, 1 partly done (11), 2 deferred (7, 15).
