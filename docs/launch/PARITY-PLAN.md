# Cardsite for Apple platforms — web parity and launch plan

**Updated:** 2026-10-12 · **Repo:** `aidenlive/CS-101126-APPS` · **Status:** Waves 0–3 code complete, **not compiled**; wave 4 waits on the owner.
**Each check below is labelled _verified_ (it was run) or _not verified_.**

## 1. Bottom line

**Status on 12 Oct 2026 (evening).** Cardsite® for Apple platforms is written to web parity: waves 0–3 are code complete, in one multiplatform SwiftUI target for iPhone, iPad, Mac and Apple Vision Pro, plus widgets, a share extension and an Apple Watch app (about 44,000 lines of Swift with StudioKit).

- **Verified on CI** (macOS 26 runners, since the repo went public):
  - every target compiles: iOS (with widgets, share extension and watch app), macOS, visionOS, watchOS;
  - `swift test`: all CardsiteKit and StudioKit tests pass;
  - UI tests: **Mac all green** (every screen, light/dark/AX5, and all 5 journeys); **iPad and iPhone** every screen and every journey pass except the AX5 Links capture, where the screen renders correctly but the harness can't confirm it (open item);
  - about 160 screenshots per run on the `screens` branch, reviewed screen by screen; the fixes from each review are in (see §12).
- **Also verified:** the contract harness against a live API built from source (332/332), the design lint.
- **Not verified:** a signed Release archive, the extensions and the watch app on devices, and the device checklist in `native-apple.md`. Those need a Mac with the Cardsite developer account (owner items A1–A3, A25).

This plan brings the app to parity with every web feature that belongs in an Apple app, in four waves, run by a group of agents working on separate directories in parallel. Every wave ends at the same gate:

- the app compiles on macOS CI;
- the CardsiteKit tests pass;
- screenshots on iPhone, iPad and Mac (light, dark, largest text size) have been reviewed against the design bar in §6.

This workspace has no Xcode, so **macOS GitHub Actions runners are the compiler, the test runner and the camera.**

## 2. Assessment

| Area | State on 11 Oct | Evidence |
|---|---|---|
| App target | Multiplatform (iOS 18 / macOS 15), XcodeGen, sidebar-adaptable `TabView` with 4 tabs | `project.yml`, `App/RootView.swift` |
| CardsiteKit | `APIClient` actor with about 25 endpoints, internal generic `send` / `sendPage` helpers, 22 tests on live-captured fixtures | `Packages/CardsiteKit` — tests **not verified** (never run) |
| StudioKit (canonical, `platform/studio/packages/swift`) | v1.2 + the 11 Oct accessibility and dark-mode fixes. Missing what design-system 1.10 has: `StudioEditorShell`, `StudioDock`, `StudioLayouts`, `StudioHaptics`, `StudioCollectionBar`, `StudioAccount`, `StudioComposition`, `StudioAccentTheme` | diff of the two copies |
| API contract | 106/106 assertions against a live API for the current endpoint set | `ContractTests/README.md` — **verified** on 11 Oct by the previous session |
| Compile | Never compiled | **Not verified** |
| Toolchain here | Go 1.24 and Postgres 16 are available, so the API can run locally for contract tests. There is no Swift or Xcode. | **Verified** |

The biggest gaps against the web dashboard are:
- no dashboard home;
- link editing is about 10% of the web form (no schedule, targeting, password, UTM or cloaking);
- six link types are missing (vCard, event, file, static, splash, payment link);
- bio pages can't be edited;
- the QR builder has 1 of 29 types;
- domains, projects, pixels, workspaces, members, inbox, uploads, data records, activity logs, API tokens, 2FA setup and preferences are all missing;
- there is no search or command palette, and no workspace switching (`X-Workspace-ID`).

## 3. Parity matrix

The status is In (built natively), Read (view in the app, edit on the web), Mac+ (on iPad and Mac only, because the job needs a large screen), or Out (left out on purpose, with the reason).

| Web feature | Apple surface | Wave | Status |
|---|---|---|---|
| Login, register, forgot/reset, 2FA code | Existing auth flow; reset links open the app (universal link, wave 3) | 0 | In |
| OAuth (Google, Facebook, Discord, LinkedIn, Microsoft) | `ASWebAuthenticationSession`. **Needs Sign in with Apple first** (Guideline 4.8), and the API has no native token exchange for it | 3 | Out until the API supports SIWA (owner decision N7) |
| API-key login | — | — | Out (developer path, not a consumer sign-in) |
| Dashboard (greeting, headline figures, quick create, sparklines, top performer, recent resources) | **Home** tab or sidebar root | 1 | In |
| Catalogue (create anything) | "New" menu, ⌘N family, iPhone + button sheet, grouped like the web | 1 | In (for the types the app supports) |
| Spotlight search + command palette | `.searchable` on Home (iPhone); ⌘K palette on iPad and Mac; Core Spotlight index of resources | 1 / 3 | In |
| Short links: list, toggle, copy/open/stats/duplicate/delete | Links list | 1 | In |
| Link detail: address and domain, destination, schedule, display rules (countries, continents, browsers, OS, devices, languages), timezone, password, click limit, expiry URL, sensitive warning, cloaking, UTM, HTTP status, forward query, splash page, project | A grouped native `Form` in sections that match the web; it autosaves the way the web tracks unsaved changes | 1 | In |
| Statistics: 7/30/90 days, tiles, daily chart, 11 breakdown dimensions | Swift Charts statistics screen, per resource and "all" | 1 | In (export is out on the web too) |
| vCards, events, payment links | Resource editors, with Add to Contacts (`CNContactViewController`) and Add to Calendar (EventKit) | 2 | In |
| File links, static pages | Editors plus upload with `fileImporter` / `PhotosPicker`, up to 10 MB | 2 | In (static ZIP upload is Mac+) |
| Splash pages | Editor: Basic tab only. Ads and code are never rendered on the web either | 2 | In (Basic) |
| Bio pages: list and settings (Settings, SEO, Theme, Branding, Targeting, Pixels) | Page settings form | 2 | In |
| Bio page editor: 85 block types | A block list with reorder, insert, toggle, duplicate and delete. The **inspector is generated from server field specs**, so one renderer covers every block, as the web does. The live preview is a `WKWebView` of the page | 2 | In. Field kinds the web shows as raw JSON stay "Edit on the web" |
| Bio editor comments, undo/redo, SSE co-editing | Comments panel; undo and redo through the server history endpoints | 3 | In (live co-editing presence is P2) |
| QR builder: 29 types, colours, transparency, size, error correction, preview, download | Builder with type picker groups, per-type fields and a live server PNG; share and save | 2 | In |
| Projects, domains (with DNS verify), pixels | Organise section | 2 | In |
| Workspaces: switcher, create, rename, delete, leave, members (invite, role, remove), activity feed | Switcher in the sidebar or toolbar; a Workspace screen | 2 | In |
| Inbox: unread, mark read, mark all | Inbox with a badge on its tab or sidebar item. Polling at first; SSE in wave 3 | 2 | In |
| Uploads gallery, data records, activity logs | Content and Account sections | 2 | In |
| Notification handlers (13 types) | Editor | 3 | Mac+ (credential entry for webhooks and bots) |
| Settings: profile, timezone, password change, 2FA enable/disable (QR + code), API tokens, delete account | Account | 1–2 | In |
| Preferences (page size, sorting, auto-copy, excluded IPs, own OpenAI key, white label) | Preferences (Mac: a Settings scene, ⌘,) | 2 | In, except the OpenAI key and white-label CSS, which are Mac+ |
| AI chat, images, text, speech, transcription | AI section, gated by the `ai_tools` capability | 3 | In **only after** a 5.1.2(i) consent screen and owner decision N8 |
| Plans, checkout, payments, referrals and withdrawals, payment processors | Plan shown read-only in Account | — | **Out**: App Review 3.1.1. The app sells nothing and links to no purchase |
| PWAs, signatures, TwiML, PWA splash generator | — | — | Out at 1.0 (web-developer tools) |
| Directory (public) | — | — | Out at 1.0 |
| Admin console | — | — | Out (staff tool) |
| Public pages (`/b`, `/vc`, `/ev`, `/u` gate, card view `@slug`) | Opened in the browser; universal links route the owner's own resources into the app | 3 | In (wave 3) |

## 4. Apple ecosystem scope

| Platform | 1.0 scope | Wave |
|---|---|---|
| **iPhone** | Full app; tab bar with Home · Links · Pages · QR · More (everything else) | 1–2 |
| **iPad** | Full app; three-column `NavigationSplitView` (sidebar in web groups → list → detail); ⌘K palette, keyboard shortcuts, pointer hover, Stage Manager sizes | 1–2 |
| **Mac** | Same target. Sidebar, toolbar, a menu bar command for every create action, a `Settings` scene, multiple windows (open a resource in a new window) | 1–2 |
| **Widgets** (iOS, iPadOS, macOS) | "Link traffic" (small/medium) and "My QR code" (shows a chosen QR) | 3 |
| **App Intents / Shortcuts / Siri** | Create short link, Show QR code, Get link clicks | 3 |
| **Share extension** | Shorten from Safari or any app | 3 |
| **visionOS** | Native destination of the same target (sidebar window, Studio surfaces, glass chrome) | 3 |
| **watchOS** | Companion: recent links with clicks, and a full-screen QR to show someone | 3 (owner decision N9) |
| **tvOS** | **Out**: a dashboard for links has no job on a TV | — |

## 5. Architecture changes (made once, in wave 0 and early wave 1)

1. **CardsiteKit by domain.** `APIClient` keeps its core (auth, transport, envelope). Each domain adds `APIClient+<Domain>.swift` and `Models+<Domain>.swift` using the internal `send` helpers. Each has fixture tests, and new fixtures come from the contract harness run against a local API. Owning files this way stops parallel agents from editing the same file.
2. **Navigation registry** (`App/Destinations.swift`), mirroring the web's `lib/navigation.ts`. It is the single source for the sidebar (Overview · Content · Organise · Account), the iPhone tabs and "More", the ⌘K palette and the menu commands. A feature registers one line.
3. **Workspace scope.** `AppModel.workspace` drives `APIClient.setWorkspace`. Switching workspaces resets the list models.
4. **One resource editor pattern.** Every link type uses `ResourceEditor`: an address field (slug + domain + live URL), type-specific sections, save state, delete. This fixes the web's modal-versus-drawer inconsistency in the app, rather than copying it.
5. **Capability gating.** `AccountPlan` capabilities decide what is shown (premium blocks, targeting, password protection, AI). A locked control says why, never offers to sell, and never links to a purchase.
6. **StudioKit 1.10 port.** Bring the missing components (`EditorShell`, `Layouts`, `Haptics`, `CollectionBar`, `Composition`, `Account`, `AccentTheme`) into the canonical package, keeping the 11 Oct fixes. Raise the package to Swift 6 language mode only once CI is green.

## 6. Design and visual bar

- **The Studio system only.** All colour, type, spacing and radius come from StudioKit tokens, with no literals in the app. A lint step in CI fails the build on `Color(red:`, `.padding(<number>)` and hex values in `Cardsite/`.
- **Liquid Glass only on chrome** (tab bar, sidebar, toolbars, the palette overlay). Content goes on opaque `StudioCard` and surface tokens. The regular glass variant is used behind text.
- **Every screen has six states:** loading (skeleton), empty (with a primary action), content, refreshing over stale data, offline, and error with retry. Each is designed, and none is a placeholder.
- **Balance across views.** The same section spacing (`StudioSpace.s6` between groups) and the same list row anatomy everywhere (`CardsiteResourceRow`: leading glyph tile, title and subtitle, state pill, trailing clicks figure; it stacks at accessibility sizes).
- **Page headers: one rule** (DESIGN-REVIEW P0-1).
  - **Full-width destinations** open with `StudioPageHead` (kicker, title, the web's description, optional actions) as their first list or form section (`ListPageHead`), and keep a `.navigationTitle` drawn inline (`inlineNavigationTitle()`) for the back button, the window title and VoiceOver. These are the resource lists, Uploads, Data Records, Projects, Domains, Pixels, Workspace, Inbox and Activity Logs. Home and Statistics are dashboards with their own `StudioPageHead`.
  - **Split-view list columns** (Links, Pages) and **Forms** (Account, Preferences, the link detail, resource editors and every sheet) keep the native large or inline title. This is a stated exception: a 360 pt column can't hold display type, and a Form's sections already carry its structure.
- **Measure.** Content is capped at a `CardsiteMeasure` width and centred: `dashboard` (1120: Home, Statistics, the Uploads gallery), `reading` (StudioKit's rhythm measure, 680: forms, lists and details) and `sheet` (560: sheet columns, full-area empty and error states), plus `narrow` (440) for the sign-in card and phone-sized previews. Lists and Forms apply it through scroll-content margins (`studioList()` / `studioForm()`), so the scroll indicator stays at the window edge. Sheets are sized with `cardsiteSheet(.form / .page)`.
- **Copy.** Title case for control labels (buttons, menu items, toolbar items, navigation, sidebar and tab titles, alert buttons); sentence case for prose (headings inside content, section headers, empty states, help text, alert titles and messages). US spelling, as `en.json`. One verb list (`ResourceVerb`: Copy Link, Open in Browser, Show Card, Statistics, Duplicate, Turn On / Turn Off, Edit…, Delete…) and one state pair ("Live" / "Off"). Curly apostrophes; alert titles read "Couldn’t …"; no "Failed to" and no "Are you sure".
- **Motion** uses Studio durations and springs; with Reduce Motion it becomes a cross-fade.
- **Accessibility gate per screen:** Dynamic Type up to AX5 without truncating primary content; VoiceOver labels on icon-only controls; contrast passes with Increase Contrast; full keyboard reachability on Mac and iPad.
- **Visual QA loop** (§7): CI renders every screen on iPhone 6.9", iPad 13" and Mac, in light, dark and AX XXXL. A design-review agent grades each screenshot against this section and files fixes before a wave closes.

## 7. Verification

| Gate | How | Where |
|---|---|---|
| Compile, iOS + macOS (+ visionOS, wave 3) | `xcodebuild build` | CI, `macos-26` |
| CardsiteKit tests | `swift test` on fixtures | CI; on Linux here only if a Swift toolchain becomes reachable (currently blocked) |
| Contract | `native-contract.sh` extended to every new endpoint, run against the API built from source with Postgres 16 and Redis **here** | Here |
| Screens | An XCUITest target launched with `-CardsiteFixtures`. A `URLProtocol` stub serves the fixtures; the test walks every destination and saves `XCUIScreen` captures. A workflow step commits the PNGs to the `screens` branch for review | CI |
| Journeys | The same UI tests assert the device checklist journeys (create link, edit, QR, delete account) | CI |
| On device | The 10-point device checklist in `native-apple.md`, on real hardware | **Owner**, before submission |

Nothing is reported as compiled, passing or working unless the gate ran.

## 8. Agent swarm

Agents own separate directories, and the lead (this session) integrates, commits and pushes. Agents don't push, because git access through the proxy is capped at 2 operations at a time.

| Agent | Owns | Wave 1 deliverable |
|---|---|---|
| **lead** | `project.yml`, `.github/`, `App/` integration, docs | Repo seeded; CI with compile + tests + screenshots; merges; status |
| **kit** | `Packages/CardsiteKit`, `ContractTests` | Domain API + models for every "In" row; fixtures from the live local API; tests |
| **shell** | `App/Destinations.swift`, `Features/Home`, `Features/Search`, `Shared/` | Navigation registry, sidebar/tabs/More, Home dashboard, ⌘K palette, workspace switcher |
| **studio** | `platform/studio/packages/swift` | 1.10 component port; token lint; component gaps the features request |
| **links** | `Features/Links`, `Features/Statistics`, `Features/ResourceEditor` | Full link form, statistics with all breakdowns, the shared `ResourceEditor` |
| **resources** | `Features/Resources/*`, `Features/Organise/*` | (Wave 2) vCard, event, payment, file, static, splash; projects, domains, pixels |
| **pages** | `Features/Pages` | (Wave 2) bio page settings and block editor |
| **qr** | `Features/QRCodes` | (Wave 2) 29-type builder |
| **account** | `Features/Account`, `Features/Workspace`, `Features/Inbox` | Settings, 2FA setup, API tokens, preferences, workspace + members, inbox, logs, uploads, data |
| **verify** | `UITests/`, `scripts/lint-*` | Fixture-served UI test harness and screenshot matrix |
| **design-review** | read-only | Grades each wave's screenshots against §6; files concrete fixes |

## 9. Waves and exit criteria

"Code complete" means the code is written, syntax-checked and design-linted. No wave has met its exit gate, because the gate needs CI (A23).

| Wave | Contents | Exit | Status (12 Oct) |
|---|---|---|---|
| **0 · Foundation** | Seed repo; CI; first compile and fix the errors it reports; split CardsiteKit into domain files; navigation registry; StudioKit port starts | CI green on iOS and macOS; existing 22 tests pass | **Code complete, not compiled.** Repo seeded (`f3add4b`). CI written with compile, tests, UI tests and the `screens` branch. CardsiteKit split into 12 domains. Registry of 21 destinations. The first compile has not happened |
| **1 · Core parity** | Home, search/palette, workspace switcher, full links and statistics, account/settings (password, 2FA, tokens) | Gate §7 + design review of every wave 1 screen | **Code complete, not compiled** (`956eceb`, `acedc31`). All listed items built. StudioKit 1.10 ported. The design review was source-only |
| **2 · Full parity** | All link types, bio page settings and editor, QR builder, organise, workspace members, inbox, uploads, data, logs, preferences | Gate + design review + contract harness green on every endpoint | **Code complete, not compiled** (`956eceb`, `acedc31`, `9efc62b`). Contract harness **green, verified**: 316/316, then 332/332 with organise |
| **3 · Ecosystem + polish** | Widgets, App Intents, share extension, universal links, visionOS, watchOS, comments/undo, SSE, Spotlight, AI (if N8), String Catalog | Gate + accessibility audit + App Store metadata and screenshots | **Ecosystem code complete, not compiled** (`9efc62b`, `0dd5145`): widgets, App Intents and App Shortcuts, share extension, visionOS destination, watchOS companion, shared session, `cardsite://` deep links. App Store metadata updated. **Not built, moved to 1.1:** universal links (A16), bio editor comments and undo/redo, SSE (the inbox polls), the Core Spotlight index, AI (N8). The String Catalog (A15) needs a build first. No screenshots yet |
| **4 · Submission** | Owner items A1–A3 and A7–A12, device checklist, TestFlight, submit | "Ready for Sale" | **Pending the owner.** It needs A23 (Actions billing) first, then A1–A3, A7–A9, A12 and A25 (App Group and keychain provisioning) |

## 10. Owner decisions

The decisions carried over from `native-apple.md` are N1 (bundle ID), N2 (production API host), N3 (launch timing), N4 (purchasing), N5 (Free plan, one slug) and N6 (login limiter). The new ones are:

| # | Decision | Recommendation |
|---|---|---|
| N7 | OAuth in the app needs Sign in with Apple in the API (Guideline 4.8) | Email and password at 1.0; add SIWA together with Google in 1.1 |
| N8 | AI tools in the app (third-party AI disclosure and consent, 5.1.2(i)) | Ship in 1.0 behind a consent screen if the AI provider is named in the privacy policy; otherwise 1.1 |
| N9 | watchOS companion at 1.0 | Yes, if wave 3 is green by launch minus 5 days; otherwise 1.1 |
| N10 | Mac+ features (notification handlers, static ZIP, white label) | Mac and iPad only, as planned |

## 11. Risks

- **macOS CI minutes and access.** This session can list workflow runs but may not be able to read logs or artifacts through the proxy, so screenshots go to a `screens` branch, which the session can read. If the repo has no macOS minutes, nothing compiles until a Mac runs it.
- **The first compile** of about 4,000 unbuilt lines will produce errors. Wave 0 is sized for that.
- **Font licences in the app binary** (A9), the **legal texts** (A8) and the **production API host** (A7) are owner-blocked and outside this plan's control.

## 12. Done this session (11–12 Oct 2026)

Each entry is labelled _verified_ (it was run) or _not verified_.

- **Wave 0.** Seeded the repo from CS-CORE: the app, CardsiteKit, StudioKit, CI and the launch docs (`f3add4b`). Split CardsiteKit by domain. Added the navigation registry. _Not verified_ (not compiled).
- **Waves 1–2: features** (`956eceb`, `acedc31`, `9efc62b`):
  - Home, the ⌘K palette and the workspace switcher.
  - The full link editor, and statistics with 11 breakdowns.
  - Every link type: vCard, event, payment, file, static and splash.
  - The bio page block editor and page settings.
  - The 28-type QR builder.
  - Organise: projects, domains with DNS verify, and pixels.
  - Workspace and members, inbox, uploads, data records, activity logs.
  - Account: password, 2FA setup, API tokens, preferences. The Mac Settings scene.

  _Not verified_ (not compiled).
- **Waves 1–2: StudioKit and the kit.** Ported the StudioKit 1.10 components and viz tokens, keeping the 11 Oct fixes. Added the design lint (`scripts/lint-design.sh`): _verified_ clean. CardsiteKit has 113 tests, which are _not verified_ (not run).
- **Contract.** Extended the harness to every parity endpoint. 316/316 (run A), 315/315 (run B), 104/104 (run C), and 332/332 with the organise steps (run D): _verified_ against the API built from source, with Postgres 16 and Redis. All 127 fixtures are live.
- **Verification harness.** In-app fixture server (`-CardsiteFixtures`), 4 screenshot passes and 5 journeys in XCUITest, and a `screens` job that publishes PNGs to the `screens` branch. _Not verified_ (never run).
- **Wave 3: ecosystem** (`9efc62b`, `0dd5145`). CardsiteWidgets (Link Traffic, My QR Code), App Intents and App Shortcuts (Create Short Link, Show QR Code, Get Link Clicks), CardsiteShare, the visionOS destination and CardsiteWatch. Also `SharedSession` (App Group and shared keychain), the WatchConnectivity relay, `cardsite://` deep links, and CI destinations for visionOS and watchOS. _Not verified_ (not compiled; it also needs signed provisioning, A25).
- **Design review.** A source-only review of every screen ([`DESIGN-REVIEW.md`](DESIGN-REVIEW.md)): 5 P0 findings and 9 systemic fixes. _Not verified_ on rendered screens.
- **Server issues found** (A26 in `native-apple.md`). The most serious is that `/spotlight` searches across all accounts, which is a **security** issue. Also: list handlers ignore `search=`; `/statistics` is cached per user, not per workspace; `scheduled_at: null` is ignored; a QR PUT ignores content edits; the web's Data filter values are wrong; `password_protection` isn't enforced; and an expiration URL can't be removed from file and static links. Reported, not fixed: this repository doesn't own the API.
- **Docs and store** (12 Oct). Rewrote `native-apple.md`, adding the device checklist 1–23 and A23–A28. Updated the App Store metadata, review notes, privacy label and screenshot plan. Added UserDefaults reason 1C8F.1 (App Group) and the Photos data type to the app's privacy manifest, which is _verified_ as a valid plist. Added the root `README.md`.
- **CI.** `project.yml` and `apple.yml` parse: _verified_ (PyYAML). Every Actions job is refused for billing: _verified_ (observed). Owner item A23.

### 12 Oct, after CI came up

| What | Result |
|---|---|
| First compile | 4 fixes (duplicate memberwise init, a type-checker time-out and a nested `ForEach` crash in the tab builder, a visionOS-unavailable API). **Verified**: every target green since |
| Unit tests | **Verified**: CardsiteKit and StudioKit pass |
| UI test harness | Reworked for each platform's navigation; relaunch onto any screen (`-CardsiteOpen`); Mac recovers a window from File ▸ New Window (A29) |
| Visual reviews of rendered screens (iPhone, iPad, Mac; light, dark, AX5) | Fixed: AX5 headlines breaking mid-word (StudioKit caps display growth); address wrapping; header actions on one line; chart's clipped last label; one sheet background; page heads in every state with inline titles on scroll; consistent account rows; no switch beside a chevron on iPhone; the matching password field; the Mac workspace switcher, sidebar width, Pages column width, doubled split-view titles, and middle-truncated rows |

