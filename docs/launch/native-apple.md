# Native apps: Apple launch plan and status

**Status:** `COMPILES ON CI · UI TESTS IN PROGRESS` · **Updated:** 2026-10-12 · **Repo:** `aidenlive/CS-101126-APPS` · Plan: [`PARITY-PLAN.md`](PARITY-PLAN.md) · Code: [`platform/apps/apple/`](../../platform/apps/apple/README.md)

The summary: Cardsite® for iPhone, iPad, Mac, Apple Vision Pro and Apple
Watch is written to web parity (PARITY-PLAN waves 0–3), with widgets, Siri
and Shortcuts, and a share extension. Since 12 Oct, when the repo went public
and GitHub Actions started running (A23), **every target compiles on CI**
(iOS with widgets, share extension and watch app; macOS; visionOS; watchOS)
and **every CardsiteKit and StudioKit test passes**.

What is proven: the builds and unit tests above; every request the app makes,
against a live API built from source (332/332 assertions); the Studio design
lint; and the first rendered screens (iPad sign-in, Mac Home and empty
states), reviewed and fixed. Not yet proven: the UI test journeys and the
full screenshot set (the harness is being fixed for each platform's
navigation), a Release archive, signing, and anything on a real device.

The apps **cannot ship on the main launch day** unless the owner items (A1–A3,
A7–A12, A25), the device checklist and App Review are done (Apple: 50% of
submissions in under 24 h, 90% in under 48 h).

## 1. Assessment (what existed on 11 Oct 2026)

Inventory of every Swift file in the CS-CORE repository and in every Cardsite
repository reachable on GitHub (CSxFINAL, CSxREPOS, Cardsite), taken on 11 Oct:

| Swift code | What it is | State |
|---|---|---|
| `platform/studio/packages/swift` (StudioKit 1.2.0) | Canonical design system, SwiftUI | Library only. A read-only audit found 3 defects users would see (no dark mode on macOS, Dynamic Type scaled twice, Mac control chrome), plus Reduce Motion ignored and a dark-mode contrast failure. All fixed on 11 Oct. Never compiled for macOS |
| `platform/studio/demos/swift`, `design-system/demos/swift` | iOS demo apps for the design system | Demos only; not products |
| `design-system/packages/swift` (1.10.0) | Reference copy (ADR 0002) | Ported into the canonical StudioKit on 12 Oct (wave 1) |
| `partners/…/neue-1.0/packages/swift` (archived) | Partner proposal | Not used |
| **Cardsite iOS / iPadOS / macOS app** | — | **Did not exist** |
| **Android** | — | **Did not exist** (no Kotlin, Gradle or manifest anywhere) |

There was no bundle ID, no Apple developer team reference, no App Store
Connect record, no icons and no metadata. A first app (sign-in, links, traffic,
basic QR, read-only pages, account) was written on 11 Oct and seeded into this
repository (`f3add4b`). Everything below was built on 11–12 Oct.

## 2. What was built (11–12 Oct 2026)

**One multiplatform SwiftUI target** (iOS 18+, iPadOS 18+, macOS 15+ and
visionOS 2+; one bundle ID; universal purchase), plus three embedded targets:
**CardsiteWidgets** and **CardsiteShare** (iOS and macOS) and
**CardsiteWatch** (watchOS 11+, embedded in the iOS app). All are generated
by XcodeGen from [`project.yml`](../../platform/apps/apple/project.yml).

Two packages sit underneath. **CardsiteKit** is the platform-neutral API
client and models: an actor `APIClient` split by domain, `SharedSession` for
the App Group and the shared keychain, and 113 tests decoding live-captured
fixtures. **StudioKit** is the design system, with the 1.10 components ported
and the 11 Oct fixes kept, and 16 tests.

Size: about 37,500 lines of Swift under `platform/apps/apple` (27,100 in the
app target including the Debug fixture server; 7,900 in CardsiteKit; 1,900 in
the widgets, share extension and watch app), plus 6,100 in StudioKit.

### Every platform: the feature set

| Area | Built |
|---|---|
| Sign-in | Email and password; two-factor step (authenticator or recovery code); create account (8–64 character password, Terms and Privacy consent); password reset by email; session token in the Keychain; the 7-day JWT expiry detected locally; an expired session signs out with a notice. No third-party login (no Sign in with Apple in the API yet) |
| Navigation | One registry (`App/Destinations.swift`) of 21 destinations in the web's groups (Overview, Content, Organise, Account). It drives the sidebar, the iPhone tabs and More, the ⌘K palette, the Go menu (⌘1–⌘7) and the New menu (every creatable type). Workspace switcher (`X-Workspace-ID`); switching resets every list. Inbox badge. `cardsite://` deep links from widgets, the share extension and Siri, held until signed in |
| Home | The web dashboard: greeting, headline figures, quick create (paste a URL or pick a type), 30 days of traffic with the top performer, recently edited resources. iPhone search lives here (`.searchable`) |
| Search | ⌘K command palette on iPad and Mac (destinations, create actions, the workspace's links; keyboard-driven; Liquid Glass as chrome). Link search uses `GET /links?search=` and filters locally, because the server ignores `search` (A26) and `/spotlight` is not scoped to the caller |
| Short links | List with swipe and context actions (copy, open, card view, statistics, duplicate, on/off, delete). Create with a random or chosen address. The full link editor in the web's sections: address and domain, destination, schedule (start, end, timezone), display rules (countries, continents, browsers, OS, devices, languages), gating (password, click limit, expiry URL, sensitive-content warning), cloaking, UTM, HTTP status, forward query, splash page, project and pixels. Unsaved-changes guard. Locked controls say which plan capability they need and never offer to sell |
| Other link types | vCards (with **Add to Contacts** through `CNContactViewController` and a `.vcf` share), events (with **Add to Calendar** through `EKEventEditViewController` and an `.ics` share), payment links, file links (upload from Files or Photos, up to 10 MB), static pages (HTML, Markdown, SVG or a ZIP site) and splash pages (the web's Basic tab). One generic list and one editor scaffold shared by every type |
| Statistics | Per resource and for the whole workspace: 7/30/90 days, four figures, a Swift Charts daily chart with an `AXChartDescriptor`, and breakdowns by all 11 server dimensions |
| Bio pages | List, create, duplicate, delete, on/off. **Block editor**: block list with reorder, insert from a library of the server's block types, toggle, duplicate and delete; an inspector generated from the server's field specs, so one renderer covers every block type, as the web does; a 409 version conflict shows who edited last; a live `WKWebView` preview. **Page settings**: Page, SEO, Theme, Branding, Display Rules and Pixels. Field kinds the web shows as raw JSON stay "Edit on the web" |
| QR codes | **Builder** for the server's 28 types in groups, with per-type fields, colours, size and error correction, and a live server-rendered preview (side by side on iPad and Mac, pinned above the form on iPhone). A code for one of my links is dynamic (it follows the link's destination). Detail, share, save to Photos (add-only), edit, delete |
| Organise | Projects (create, rename, recolour, delete), domains (add, edit, DNS verify with the server's own instructions, delete), pixels (create, edit, delete) |
| Library | Uploads (gallery and list; add from Photos or Files; copy address; delete), data records (collected form data), activity logs (sign-ins and security events, search, device filter) |
| Workspace | Create, rename, delete or leave; members (invite by email, change role, remove); activity feed |
| Inbox | Notifications with unread state, mark read, mark all read, badge |
| Account | Profile and name; timezone; change password; **two-factor setup** (QR and secret, verify, 10 recovery codes, disable with password); **API tokens** (create with scopes, the secret shown once, revoke); preferences (page size, sorting, auto-copy, excluded IPs); plan shown read-only; Privacy, Terms, Support; sign out; **in-app account deletion** (App Review 5.1.1(v)). The OpenAI key and white-label settings are kept but edited on the web only (N10) |
| States | Loading, empty with a primary action, content, refreshing over stale data, offline, and error with retry, on every screen; form errors inline |
| Design | Studio tokens, type and components throughout; the design lint (`scripts/lint-design.sh`) passes with no colour, padding, spacing, radius or font literal in `Cardsite/`; Brand Kit mark as vector. Liquid Glass only on system chrome and the ⌘K palette |
| Debug | A fixture server (`Cardsite/Debug`, Debug builds only) answers every API call from the live-captured fixtures, so UI tests and screenshots need no server. Launch with `-CardsiteFixtures` |

### By platform

| Platform | What is specific to it |
|---|---|
| **iPhone** | Tab bar: Home · Links · Pages · QR · More (everything else, grouped like the web). Search on Home. Sheets for create and edit; the page editor collapses to a stack with Preview as a sheet. Haptics on key actions |
| **iPad** | `TabView(.sidebarAdaptable)`: sidebar in the web's groups, list and detail in split views. ⌘K palette, the Go and New keyboard shortcuts (hold ⌘ to see them), pointer hover, Stage Manager sizes. QR builder and page editor side by side |
| **Mac** | The same target, native: sidebar, toolbar, menu bar commands for every destination and create action (⌘N short link, ⇧⌘N QR code, ⌘K palette), a `Settings` scene (⌘,) with General, Security and Preferences, 1100 × 760 default window, App Sandbox and hardened runtime |
| **visionOS** | A native destination of the same target (not "Designed for iPad"): the iPad layout in a window, Studio surfaces for content, system glass for chrome, StudioKit glass and haptics gated for visionOS, a solid image-stack app icon |
| **watchOS** | CardsiteWatch: recent short links with their clicks, a link's day and week, and a **full-screen QR code** on white at full brightness to show someone. The session arrives from the iPhone over WatchConnectivity on sign-in, workspace switch and sign-out, and is kept in the watch's own keychain, so it opens without the phone nearby. Colours mirror Studio tokens (`WatchPalette`) because StudioKit doesn't build for watchOS |
| **Widgets** (iPhone, iPad, Mac) | **Link Traffic** (small: one link's clicks and 7-day sparkline, the most-clicked link by default; medium: a chosen link first, then the top links) and **My QR Code** (a chosen code, or the newest; the image is cached in the App Group so it shows offline). Both configurable with App Intents, both show a sign-in prompt until the app has shared a session |
| **App Intents** | **Create Short Link** (destination, optional custom address; copies the result), **Show QR Code** (full size in Siri or Shortcuts) and **Get Link Clicks** (a number Shortcuts can pass on). App Shortcuts phrases such as "Shorten a link with Cardsite" and "Show my Cardsite QR code" work without setup; entity suggestions refresh when the session or workspace changes |
| **Share extension** (iPhone, iPad, Mac) | "Shorten with Cardsite" from Safari or any app: finds the web address in a shared URL or text, takes an optional custom address, creates the link, then offers Copy. Reads the session the app shares; asks the person to sign in to the app when there is none |

The app shares its session with the extensions through `SharedSession`: the
context in the App Group `group.$(CARDSITE_BUNDLE_ID)`, the token in the
keychain group `$(AppIdentifierPrefix)$(CARDSITE_BUNDLE_ID).shared`. An
unsigned build leaves the prefix empty and sharing is then off, so the
widgets, the share extension and the intents only work in a signed build
with both groups provisioned (A25).

### Release configuration

XcodeGen `project.yml`; Debug and Release xcconfigs; Info.plist with
`UILaunchScreen` (required by the OS 27 SDK), ATS, export compliance
(`ITSAppUsesNonExemptEncryption = NO`), the `cardsite://` URL scheme, and
purpose strings for Photos (add only), Contacts and the local network (Debug
API only); entitlements for every target; the privacy manifest; app icons (iOS
light, dark and tinted; macOS; visionOS; watchOS); App Store metadata, review
notes, privacy label, age rating and screenshot plan
([`AppStore/README.md`](../../platform/apps/apple/AppStore/README.md)).

### CI

[`.github/workflows/apple.yml`](../../.github/workflows/apple.yml), on pushes to
`main`, `claude/**` and `ws/**` and on pull requests:

- `fixtures`: the contract fixtures and the test copies are in sync;
- `lint`: the Studio design lint;
- `kit`: `swift test` for CardsiteKit and StudioKit, and CardsiteKit built for watchOS;
- `app`: the app built for the iOS Simulator (with the embedded watch app), macOS and the visionOS Simulator, and the watch app on its own;
- `screens`: the UI tests on iPhone 17 Pro Max, iPad Pro 13" and Mac, which run the journeys and capture every screen in light, dark and AX XXXL;
- `screens-publish`: commits the PNGs to the orphan `screens` branch under `runs/<sha>/`.

Compiler errors become check-run annotations. Jobs run since 12 Oct.

### Supporting changes

- **API** (`api` workstream, 11 Oct, CS-CORE): deleting an account cancels the paid subscription first and refuses with 409 `active_subscription` if it can't (ADR-0175); the general rate limiter sends `Retry-After`; the OpenAPI contract, `API.md` and `SECURITY.md` were corrected where they disagreed with the code. `go vet` and `go test` passed against Postgres 16.
- **Contract harness** ([`ContractTests/native-contract.sh`](../../platform/apps/apple/ContractTests/README.md)): extended on 12 Oct to every endpoint the parity plan uses, including the 2FA sign-in challenge, organise CRUD and DNS verify. It found the server issues in A26.

### Copy style

- **Copy.** Title case for control labels (buttons, menu items, toolbar items, navigation, sidebar and tab titles, alert buttons); sentence case for prose (headings inside content, section headers, empty states, help text, alert titles and messages). US spelling, as `en.json`. One verb list (`ResourceVerb`: Copy Link, Open in Browser, Show Card, Statistics, Duplicate, Turn On / Turn Off, Edit…, Delete…) and one state pair ("Live" / "Off"). Curly apostrophes; alert titles read "Couldn’t …"; no "Failed to" and no "Are you sure".

## 3. Verification: what is and isn't proven

| Check | Result | How |
|---|---|---|
| Every request and response the app uses | **Verified** against a live API: **316/316** (run A, wrote the fixtures), 315/315 (run B, default limiter plus the 429 probe), 104/104 (run C, no parity section), then **332/332** with the organise steps (run D, 12 Oct) | `native-contract.sh` against the API built from source with Postgres 16 and Redis, locally. Details: `ContractTests/README.md` |
| Fixtures the tests and the fixture server use | **Verified** live: all 127 captured from those runs, none synthetic | Same runs; `scripts/sync-fixtures.sh` |
| Swift syntax, app, extensions, watch, CardsiteKit, StudioKit | **Verified** (0 errors) | tree-sitter-swift parse. Another agent is editing Swift now, so re-run before the next commit |
| Studio design lint | **Verified** clean (re-run 12 Oct) | `scripts/lint-design.sh` |
| `project.yml` and `apple.yml` parse | **Verified** (re-run 12 Oct) | PyYAML. That XcodeGen accepts the spec is **not verified** |
| Code review as a compiler would read it | **Done**, not proof: Swift 6 concurrency, availability and platform gates were checked by reading (commits `9efc62b`, `0dd5145`) | Source review only |
| Design review | **Source-only**, 12 Oct: 5 P0, about 20 P1 and 18 P2 findings plus 9 systemic fixes ([`DESIGN-REVIEW.md`](DESIGN-REVIEW.md)). No screen was rendered. Fixes in progress | Read the SwiftUI source |
| App compiles: iOS (with widgets, share extension and embedded watch app), macOS, visionOS, watchOS | **Verified** 12 Oct on CI (Xcode 26, `macos-26`), Debug, signing off. First green at `d886216` after 4 fix rounds | CI `app` matrix. A Release archive is **not verified** |
| CardsiteKit tests (113) and StudioKit tests (16) | **Verified**: all pass on CI, and CardsiteKit also builds for watchOS | CI `kit` |
| UI tests: 4 screenshot passes and 5 journeys on iPhone, iPad, Mac | **Running, not yet green**: the app launches in fixture mode on the iPhone 17 Pro Max simulator, the iPad Pro 13" simulator and the Mac runner. The harness is being fixed for platform navigation | CI `screens` |
| Screenshots | **Partly produced**: first iPad (sign-in/up) and Mac (empty states, Home) captures on the `screens` branch and reviewed. Fixes from them are in | CI `screens` → `screens` branch |
| Widgets, share extension, intents, watch session relay | **Not verified**; they also need a signed build with A25 provisioned | Device only |
| Critical journeys on a device | **Not verified** | [Device checklist](#device-checklist) |
| API changes (ADR-0175, `Retry-After`) | **Verified** on 11 Oct | `go test ./...` with Postgres, in CS-CORE |

The first CI compile (12 Oct, after the repo went public) needed four small
fixes: a duplicate memberwise initializer, a type-checker time-out and a
nested `ForEach` crash in the tab builder, and an API that doesn't exist on
visionOS. Every target has built since.

### Device checklist

Run before submitting. Use an iPhone (and the Simulator at the largest
Dynamic Type size), an iPad (portrait, landscape and Split View), a Mac (light
and dark), an Apple Watch paired with the iPhone, and Apple Vision Pro (or its
Simulator). Use a signed build, so the App Group and keychain group exist.

**Account and session**
1. Create an account; Home shows its empty state. Sign out, then sign in. A two-factor account asks for a code, and a recovery code works.
2. Account ▸ Two-Factor: set it up with an authenticator app by scanning the QR, verify, and save the 10 recovery codes. Sign out and back in with a code. Turn it off with a wrong password (error, still on), then with the right one.
3. Account ▸ API Tokens: create a token with scopes. The secret shows once, and `curl -H "Authorization: Bearer cst_…" <host>/api/v1/links` works. Revoke it, and the same call gets 401.
4. Change the password with a wrong current password: an error, and still signed in. With the right one, sign in again with the new password.
5. Workspace: create a second workspace and switch to it. Every list empties, Home and the widgets follow, and the watch follows. Invite a member, change their role and remove them. Rename, then delete or leave.

**Short links and other types**

6. New Short Link with a random address: it appears at the top and opens in detail. Copy puts `https://card.site/…` on the clipboard. Open and Card View open the browser, and the address resolves.
7. A taken address shows an error on the address field. A second link on a Free account gives the plan-limit message, with no purchase prompt.
8. **Link editor**, each section, saved and checked from another device: destination; schedule (a start in the future means not live yet; clearing the schedule, see A26); display rules (block your own country, then not-found); password gate; click limit; expiry URL; sensitive warning; cloaking; UTM (the parameters arrive); HTTP status; forward query; splash page; project; pixels. Leaving with unsaved changes asks first. Turn the address off: not-found. Back on: it works.
9. **Every link type**, created, edited, opened publicly and deleted:
   - vCard: Add to Contacts shows the system sheet and saves only on confirm, with no Contacts permission prompt; the `.vcf` shares.
   - Event: Add to Calendar shows the system editor, with no Calendar permission prompt; the `.ics` shares.
   - Payment link: opens the checkout URL; a non-http(s) URL is refused.
   - File link: upload from Files and from Photos; over 10 MB is refused.
   - Static page: HTML and ZIP.
   - Splash page: attach it to a link; the countdown shows.
10. Statistics: visit an address from another device. After refresh the figures, chart and each of the 11 breakdowns update, for 7, 30 and 90 days, per link and for everything. VoiceOver reads the chart summary.

**Pages, QR codes and Organise**

11. **Bio page block editor**: create a page; add blocks of several kinds from the library; edit each in the inspector; reorder by drag and with the keyboard; toggle; duplicate; delete. The preview follows. Edit the same block on the web first: the app shows the conflict and who edited. A premium block on a lower plan says why it's locked, with no offer. Page Settings: each section saves and shows on the public page.
12. **QR builder**: make one code of each group (URL, text, Wi-Fi, vCard, event, email, SMS, location and the rest). The preview updates as you type. Colours, size and error correction apply. Scan each with the Camera app. A code for one of my links follows a destination change. Edit a stored code's content and confirm the change sticks (see A26). Share, and Save Image (the add-only Photos prompt shows its purpose string).
13. **Organise**: create, rename, recolour and delete a project; links in it stay. Add a domain, see the DNS instruction from verify, point it, verify, then delete. Create, edit and delete a pixel.
14. Uploads: add an image and a file, copy the address, delete. Data Records lists form submissions from a bio page block. Activity Logs lists the sign-ins from steps 1–4 and searches.
15. Inbox: an unread notification shows the badge. Mark it read, then mark all read.

**Ecosystem**

16. **Widgets** on the iPhone Home Screen, the iPad and the Mac desktop. Link Traffic small and medium, unconfigured and set to a link; the figures match Statistics. My QR Code set to a code: it scans, and it still shows in airplane mode. Signed out, both show a sign-in prompt, and tapping opens the app.
17. **Share extension**: from Safari, Share ▸ Cardsite shortens the page, with and without a custom address, and Copy works. From Notes, with text that contains a URL. Signed out, it asks you to sign in to the app.
18. **Siri and Shortcuts**: "Shorten a link with Cardsite" asks for the destination and copies the result. "Show my Cardsite QR code" shows a scannable code. "How many clicks on … in Cardsite" answers. All three appear in the Shortcuts app.
19. **Apple Watch**: after signing in on the iPhone, the watch lists recent links with clicks. A link shows its day and week. The full-screen QR scans from another phone. With the phone out of range, the watch still opens signed in. Signing out on the phone signs the watch out.
20. **visionOS**: the app opens in a resizable window with the sidebar, content on opaque surfaces and glass only on chrome. Look-and-pinch reaches every control. Create a link and a QR code.

**Every platform**

21. Airplane mode: lists keep their data with "Not up to date". A first load shows "You're offline" with Try Again.
22. Delete Account with a wrong password: an error, and still signed in. With the correct password: signed out with a notice, and signing in again fails.
23. Accessibility: VoiceOver through sign-in, Home, a list, the link editor, the block editor, the QR builder and delete. Also Reduce Motion, Reduce Transparency, Increase Contrast and AX5 text. On the Mac and an iPad keyboard: ⌘N, ⇧⌘N, ⌘K, ⌘1–⌘7, ⌘, (Mac), Tab through forms, Return submits.

## 4. Launch checklist (Apple)

P0 blocks submission · P1 should be in 1.0 · P2 after. The owner is a
workstream or **owner** (a decision or account action only the owner can
take). "Built" means the code is written but not compiled.

| # | Item | Owner | Acceptance | State |
|---|---|---|---|---|
| A1 | Apple Developer Program membership for Cardsite, Inc. (organisation, D-U-N-S) | owner | Team ID known | **unknown** |
| A2 | Decide bundle ID (N1) and production API host (N2); set `Config/*.xcconfig` | owner → apple | Values committed | open |
| A3 | App Store Connect record (iOS, macOS and visionOS; universal purchase; the watch app inside the iOS app), agreements, tax, banking, DSA trader status | owner | Record exists | open |
| A4 | First Xcode 27 build of every target (app on iOS, macOS and visionOS; widgets; share extension; watch app); fix compile errors; zero Swift 6 concurrency errors | apple | CI `app` green | **Done** 12 Oct: all four `app` jobs green |
| A5 | `swift test` green for CardsiteKit (113) and StudioKit (16) | apple | CI `kit` green | **Done** 12 Oct: `kit` green |
| A6 | Device checklist 1–23 passes on iPhone, iPad, Mac, Apple Watch and Vision Pro; UI tests green | apple, verify | CI `screens` green; screenshots on the `screens` branch | open |
| A7 | Production API reachable over HTTPS with the deploy (G5: O1, O2) | infra, owner | `curl https://<host>/api/v1/plans` → 200 | **blocked on owner** (O1, O2) |
| A8 | Legal texts approved (G7: O5); the Privacy Policy matches the privacy label | owner, content | Counsel sign-off; label confirmed | **blocked on owner** (O5) |
| A9 | Font licences cover embedding Certia, Bounded and Editorial New **in an app binary**, including the extensions (O6, extended) | owner | Written confirmation | **blocked on owner** (O6). Since 12 Oct the repo is public, so the font files under `platform/studio/packages/swift/Sources/StudioKit/Resources/Fonts` are publicly downloadable; confirm the licences allow that, or move the repo back to private with Actions billing fixed |
| A10 | App Review demo account on a paid plan, seeded; screenshots for every required size (see A24 for iPhone Duo) | apple, owner | Uploaded | open. The plan is in `AppStore/README.md`; CI captures iPhone, iPad and Mac once A23 is fixed |
| A11 | Submit for review; respond to findings | apple | "Ready for Sale" | open |
| A12 | CAPTCHA stays **off** for login and register while the app is live (a native client can't complete it) | owner | Admin setting confirmed off | open |
| A13 | Login limiter (6 per 10 min **per IP, successes included**) reviewed for mobile carriers behind shared IPs | api, owner | Decision recorded | open (P1) |
| A14 | Free plan allows one link: the server counts every address against `custom_slugs_limit`, but the Overview says auto-generated addresses are unlimited (roadmap #47) | api, owner | Random addresses don't count | open (P1; the app works, but Free is thin) |
| A15 | Strings exported to a String Catalog; English only at 1.0 | apple | `.xcstrings` in the project | open (P1). String extraction is on; no catalog yet, because one needs a build |
| A16 | Universal links (`card.site/…` opens the app); needs `apple-app-site-association` on card.site | apple, infra | AASA served | P2. Not built; `cardsite://` covers widgets, the share extension and Siri |
| A17 | Push notifications (lifecycle notices, traffic milestones); the API has no APNs support | api, apple | — | P2. The inbox polls |
| A18 | Sign in with Apple and Google in the app; the API needs native token exchange and Apple token revocation on deletion | api, apple | — | P2 |
| A19 | In-app purchase or a US-only external purchase link (3.1.1 / 3.1.3) | owner | Decision | P2 (1.0 sells nothing) |
| A20 | Widgets (Link Traffic, My QR Code), App Intents (Create Short Link, Show QR Code, Get Link Clicks), share extension | apple | Device checklist 16–18 | **Built, not compiled**. Now in 1.0 scope |
| A21 | iPhone Duo layout and screenshots | apple | — | Moved to A24 |
| A22 | Bio page editing (blocks and settings) and file editing in the app | apple | Device checklist 9, 11 | **Built, not compiled**. Also built: watchOS companion (N9) and the visionOS destination; device checklist 19–20 |
| A23 | **Fix GitHub Actions billing** on `aidenlive/CS-101126-APPS`. Every job is refused: "recent account payments have failed or your spending limit needs to be increased". Until then nothing compiles, no test runs and no screenshot exists | **owner** | A workflow run starts; `apple` jobs report | **Done** 12 Oct: the repo was made public, which makes the standard runners free |
| A24 | iPhone Duo (foldable, iOS 27.1, from 23 Oct 2026) layout: `ArrangementView`, hinge-aware `ReservedRegion`, both displays; screenshots (outer 1398 × 2034, inner 2007 × 2853) | apple | Duo screenshots uploaded | P1. Required from **April 2027** for builds made with the iOS 27.1 SDK or later. Not needed for a 1.0 built with the 27.0 SDK |
| A25 | Provision the **App Group** `group.<bundle ID>` and the **keychain group** `<team>.<bundle ID>.shared` for the app, CardsiteWidgets (`.widgets`), CardsiteShare (`.share`) and CardsiteWatch (`.watchkitapp`); App IDs for all four bundles; the watch app ID set as a companion of the iOS app | owner → apple | A signed build shares the session: the widget and share extension see the signed-in user | open. Needs A1 and N1. Unsigned CI builds turn sharing off |
| A26 | **Server issues found by the agents**, to fix in `apps/api`. The app works around each one where it can | api | Each fixed, with a contract assertion turned from `note` to pass | open; see the list below |
| A27 | Privacy manifests for the **extension and watch bundles**. App Store Connect checks required-reason APIs per bundle: CardsiteWidgets and CardsiteShare read the App Group's `UserDefaults` (1C8F.1); CardsiteWatch uses `UserDefaults.standard` (CA92.1) | apple | `PrivacyInfo.xcprivacy` in each target; upload passes without ITMS-91053 | Built: `PrivacyInfo.xcprivacy` in CardsiteWidgets/, CardsiteShare/, CardsiteWatch/ (CA92.1 + 1C8F.1, no tracking), each a resource in `project.yml`; not yet verified by an App Store Connect upload |
| A28 | Design review P0s and the systemic fixes S1–S9 applied, then re-graded on rendered screenshots | apple, design-review | No P0 open on the `screens` branch | open. Fixes in progress; the review so far is source-only |

#### A26: server issues (fix in the API)

1. **SECURITY: `GET /spotlight` searches every account.** It returns every
   account's enabled links and directory-listed bio pages, not the caller's.
   That leaks other customers' resources to any signed-in user. Scope it to
   the caller and the current workspace before launch, web and app alike.
   The app never calls it.
2. **`GET /links` and the other list handlers ignore `search=`.** They read
   only `page` and `results_per_page`. The app sends `search` and also
   filters the first 100 rows locally, so its search misses older links
   until this is fixed.
3. **`GET /statistics` is cached per user, not per workspace**, for 5 minutes,
   and creates don't clear it. After a workspace switch the figures can show
   the other workspace's numbers. Key the cache by workspace and invalidate
   it on writes.
4. **`scheduled_at: null` sent to clear a schedule is ignored.** The
   stored schedule stays, so clearing it in the editor doesn't take effect.
5. **A QR `PUT` ignores content edits unless `embedded_data` is cleared.** The
   web has the same bug. The stored code keeps encoding the old content.
6. **The web's Data filter values don't match the server's block types**
   (`GET /data?type=`), so the web's type filter doesn't match the records
   it should. The app sends the server's own types. Align the web's values.
7. **The short-link `password_protection` plan capability isn't enforced
   server-side.** The clients hide the field on plans without it, but the
   API accepts a password from any plan.
8. **File and static link updates can't remove an expiration URL.** Once
   set, the multipart `PUT` gives no way to clear `expiration_url`.

Further quirks the client already tolerates are in
[`ContractTests/README.md`](../../platform/apps/apple/ContractTests/README.md#server-quirks-the-client-must-tolerate-asserted-as-note).
For example, `PUT /links` returns timestamps one write behind, `GET /user` is
cached and not cleared by `PUT /account`, and the bcrypt `password_hash` is
sent to clients. That last one is worth fixing alongside item 1.

### Remaining steps to submission

In order:

1. **Fix Actions billing (A23)**, then push. CI compiles every target and runs the tests and UI tests. Fix the annotated errors until `apple` is green, and read the screenshots on the `screens` branch. Without CI, use a Mac with Xcode 27: `brew install xcodegen && cd platform/apps/apple && xcodegen generate && open Cardsite.xcodeproj`, then build each scheme and press ⌘U.
2. Grade the rendered screens against PARITY-PLAN §6 and [`DESIGN-REVIEW.md`](DESIGN-REVIEW.md); fix the P0s (A28).
3. With the Cardsite, Inc. developer account (A1): confirm N1 and N2, `cp Config/Signing.example.xcconfig Config/Signing.xcconfig`, set `DEVELOPMENT_TEAM`, and register the four App IDs, the App Group and the keychain group (A25). Add the extension and watch privacy manifests (A27).
4. Run the stack (`make -C platform up` in CS-CORE), point Debug at it, and walk the device checklist on the Simulators, then on devices against staging.
5. Ask the `api` workstream for A26 (item 1 before launch at the latest).
6. Create the App Store Connect record; paste `AppStore/metadata`, the privacy label, the age rating and the review notes; create and seed the demo account.
7. Product ▸ Archive for iOS (with the watch app) and macOS, and for visionOS; upload; run the device checklist again in TestFlight.
8. Capture the screenshots for every required size; submit all platforms together.

**Fastest path:** step 1 takes a day once CI runs (more if the first compile
is rough), steps 2–4 another one to two days, steps 6–8 a day, then review
takes one to two days. Launch the web product on its day and the apps when
review passes (N3). Apple's expedited review is for critical fixes and events.

## 5. Owner decisions (native)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| N1 | Bundle ID (permanent; the extensions, watch app, App Group and keychain group derive from it) | `com.cardsite.app` · other | `com.cardsite.app` |
| N2 | Production API host for native | `https://cardsite.com` (Caddy passes `/api/*`) · `https://prod.cardsite.io` (openapi `servers`) | The host the web app calls in production; set in `Config/Release.xcconfig` |
| N3 | Apps on launch day or when review passes | Same day (needs every step done ≥3 days before) · fast-follow | Fast-follow by days; don't hold the web launch |
| N4 | Purchasing in the app | None (1.0) · IAP · US external link | None at 1.0 (as built) |
| N5 | Free plan's single address (A14) | Fix #47 before app launch · ship as is | Fix #47: the app's default is a random address |
| N6 | Login rate limit for mobile (A13) | Count failures only · per account and IP · keep | Count failures only, per account and IP |
| N7 | OAuth in the app needs Sign in with Apple in the API (4.8) | Email and password at 1.0 · SIWA first | Email and password at 1.0; SIWA with Google in 1.1 |
| N8 | AI tools in the app (5.1.2(i) disclosure and consent) | 1.0 behind consent · 1.1 | 1.1. Not built |
| N9 | watchOS companion at 1.0 | Yes · 1.1 | Yes if device checklist 19 passes by launch minus 5 days; it is built |
| N10 | Mac+ features (notification handlers, static ZIP, white label) | Mac and iPad only · web only | The OpenAI key and white label stay on the web; static ZIP is allowed everywhere with a note on iPhone |
| N11 | Fix Actions billing or provide a Mac (A23) | Fix billing · self-hosted Mac runner · a Mac by hand | Fix billing: CI is the compiler, the test runner and the screenshot camera |

## 6. Android fast-follow (end of Q4)

See `docs/launch/native-android.md` in CS-CORE. Nothing for Android is in
this repository.
