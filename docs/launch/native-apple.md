# Native apps — Apple launch plan and status

**Status:** `BUILT, NOT YET COMPILED` · **Updated:** 2026-10-11 · **Owner:** `apple` workstream ([`.claude/agents/apple-native.md`](../../.claude/agents/apple-native.md)) · Code: [`platform/apps/apple/`](../../platform/apps/apple/README.md)

The honest summary: on 11 Oct 2026 there were **no Cardsite native apps** to
finish. A first, complete Cardsite app for iPhone, iPad and Mac was written
that day, on the real API contract and the canonical design system. It has
**not been compiled or run**, because no Mac or Xcode was available. It
**cannot ship on the main launch day** unless the steps in
[Remaining steps](#remaining-steps-to-submission) are done first and App
Review passes (Apple: 50% of submissions in under 24 h, 90% in under 48 h).

## 1. Assessment (what existed on 11 Oct 2026)

Inventory of every Swift file in this repository and in every Cardsite
repository reachable on GitHub (CSxFINAL, CSxREPOS, Cardsite):

| Swift code | What it is | State |
|---|---|---|
| `platform/studio/packages/swift` (StudioKit 1.2.0) | Canonical design system, SwiftUI | Library only. Read-only audit found 3 defects users would see (macOS had no dark mode, Dynamic Type double-scaled, Mac control chrome), plus Reduce Motion ignored and a dark-mode contrast failure. **All fixed 11 Oct** ([CHANGELOG](../../platform/studio/CHANGELOG.md), Unreleased). Never compiled for macOS before |
| `platform/studio/demos/swift`, `design-system/demos/swift` | iOS demo apps for the design system | Demos only; not products |
| `design-system/packages/swift` (1.10.0) | Reference copy (ADR 0002) | Not used |
| `partners/…/neue-1.0/packages/swift` (archived) | Partner proposal | Not used |
| **Cardsite iOS / iPadOS / macOS app** | — | **Did not exist** |
| **Android** | — | **Did not exist** (no Kotlin, Gradle or manifest anywhere) |

Not in the launch roadmap, the Overview or any ADR before today. No bundle
ID, no Apple developer team reference, no App Store Connect record, no
icons, no metadata existed.

## 2. What was built (11 Oct 2026)

**One multiplatform SwiftUI app** (one target, iOS 18+ / iPadOS 18+ /
macOS 15+, one bundle ID, universal purchase) plus **CardsiteKit**, a
platform-neutral Swift package. 4,200 lines of Swift.

| Area | Built |
|---|---|
| Sign-in | Email + password; two-factor step (authenticator or recovery code); create account (8–64 char password, Terms/Privacy consent); password reset by email; session token in the Keychain (this device only); 7-day JWT expiry detected locally; expired session signs out with a notice |
| Links | List with search, pull-to-refresh, pagination, swipe and context actions; create (destination + random or chosen address, client-side validation, "taken" shown on the field, plan limit explained); detail with copy / share / open / **card view** (`card.site/@slug`); change destination; turn an address off and on; release-window warning; delete with confirmation |
| Traffic | Views, average daily visitors, daily chart (Swift Charts), top referrers and countries, 7/30/90 days |
| QR codes | List, create for **one of my links** (dynamic: follows the link's destination) or any URL, detail with crisp image, share/save PNG, copy target, delete |
| Pages | Bio pages listed with share / open / card view (editing stays on the web) |
| Account | Profile and name edit, plan shown read-only, 2FA status, Privacy / Terms / Support, version, sign out, **in-app account deletion** (App Review 5.1.1(v)) with a password-reset path |
| States | Loading, empty (with a primary action), offline, error with retry, refresh-failed banner over stale data, every form error inline |
| Platform | iPhone tab bar; iPad tab bar ⇄ sidebar with list/detail split; Mac sidebar, split view, File ▸ New Short Link (⌘N) / New QR Code (⇧⌘N), sandbox; system Liquid Glass on bars only, opaque Studio surfaces for content (HIG) |
| Design | Studio tokens, type and components throughout; no hard-coded colours or spacing in the app; Brand Kit mark used as vector, never redrawn |
| Release config | XcodeGen `project.yml`, Debug/Release xcconfigs, Info.plist (launch screen key required by the OS 27 SDK, ATS, export compliance, photo-add string), macOS entitlements, privacy manifest, app icons (iOS light/dark/tinted, macOS), App Store metadata, review notes, privacy label, age rating, screenshot plan ([`AppStore/README.md`](../../platform/apps/apple/AppStore/README.md)) |
| CI | [`.github/workflows/apple.yml`](../../.github/workflows/apple.yml): fixture sync check, `swift test`, app build for iOS Simulator and macOS |

Supporting changes made the same day:

- **API** (`api` workstream): deleting an account now cancels the paid subscription first and refuses with 409 `active_subscription` if it can't ([ADR-0175](../../platform/docs/decisions/0175-deleting-an-account-cancels-its-subscription-first.md)). The general rate limiter sends `Retry-After`. The OpenAPI contract, `API.md` and `SECURITY.md` were corrected where they disagreed with the code: error envelope, link fields, pagination, the 2FA flag, the QR image, checkout, the `X-Requested-With` requirement and the 7-day JWT. `go vet` and `go test` pass against Postgres 16.
- **Contract harness**: [`ContractTests/native-contract.sh`](../../platform/apps/apple/ContractTests/README.md) proved every request the app makes against a live API (106/106 assertions) and captured the 30 response fixtures the Swift tests decode.

## 3. Verification — what is and isn't proven

| Check | Result | How |
|---|---|---|
| Every request/response the app uses | **Verified** against a live API | `native-contract.sh` → 106 pass, 0 fail (API + Postgres 16 + Redis, local) |
| Swift syntax, all app + StudioKit files | **Verified** (0 errors) | tree-sitter-swift parse; checker confirmed to flag a broken file |
| Code review as a compiler would read it | **Done** by an independent reviewer: 3 blockers and 5 major issues found, **all fixed**; minor items fixed except as listed below | Report: every StudioKit call checked against its signature, every request against the contract |
| CardsiteKit unit tests (22) | **Written, not run** | Need `swift test` on a Mac (CI job `apple/kit`) |
| App compiles (iOS, macOS) | **Not verified** | Needs Xcode 26+ (CI job `apple/app`, blocked by O19) |
| Critical journeys on device | **Not verified** | See [device checklist](#device-checklist) |
| API changes (ADR-0175, Retry-After) | **Verified** | `go test ./...` with Postgres |
| StudioKit fixes | **Syntax + token checks verified**; not compiled | `npm run verify`, contrast, kit sync, parity all pass |

Expect the first Xcode build to surface some compile errors. Nothing here
was compiled. Budget half a day for them.

### Device checklist

Run before submitting, on an iPhone (and the Simulator at the largest Dynamic Type size), an iPad (portrait and landscape, Split View), and a Mac (light and dark):

1. Create account → lands on Links, empty state shows. Sign out → sign in → two-factor account asks for a code; a recovery code works.
2. New Short Link with a random address → appears at the top, opens in detail; Copy puts `https://card.site/…` on the clipboard; Open and View Card open the browser; the address resolves.
3. Taken address → error on the address field. Second link on a Free account → plan-limit message (no purchase prompt).
4. Change destination → visiting the address goes to the new destination. Turn the address off → not-found; back on → works.
5. Visit the address from another device → traffic chart and referrers update after refresh.
6. New QR Code for a link → scan it with the Camera app → opens the link. Share Image → Save Image works (Photos permission prompt shows the purpose string).
7. Pages tab lists a bio page made on the web.
8. Airplane mode → lists keep data with "Not up to date"; first load shows "You're offline" with Try Again.
9. Delete Account with a wrong password → error, still signed in; correct password → signed out with notice; signing in again fails.
10. VoiceOver through sign-in, list, detail and delete; Reduce Motion on; Increase Contrast; Mac keyboard: ⌘N, ⇧⌘N, Tab through forms, Return submits.

## 4. Launch checklist (Apple)

P0 blocks submission · P1 should be in 1.0 · P2 after. Owner is a workstream (see [`AGENTS.md`](../../AGENTS.md#workstreams)) or **owner** (a decision or account action only the owner can take).

| # | Item | Owner | Acceptance | State |
|---|---|---|---|---|
| A1 | Apple Developer Program membership for Cardsite, Inc. (organisation, D-U-N-S) | owner | Team ID known | **unknown** |
| A2 | Decide bundle ID (N1) and production API host (N2); set `Config/*.xcconfig` | owner → apple | Values committed | open |
| A3 | App Store Connect record (iOS + macOS, universal purchase), agreements, tax, banking, DSA trader status | owner | Record exists | open |
| A4 | First Xcode 26+ build of iOS and macOS; fix compile errors; zero Swift 6 concurrency errors | apple | `apple` CI green | open — needs a Mac (or CI once O19 is fixed) |
| A5 | `swift test` CardsiteKit (22 tests) green | apple | CI `apple/kit` green | open |
| A6 | Device checklist 1–10 passes on iPhone, iPad, Mac | apple, verify | Screenshots saved under `docs/launch/audit/screens/apple/` | open |
| A7 | Production API reachable over HTTPS with the deploy (G5: O1/O2) | infra, owner | `curl https://<host>/api/v1/plans` → 200 | **blocked on owner** (O1, O2) |
| A8 | Legal texts approved (G7: O5): Privacy Policy matches the privacy label | owner, content | Counsel sign-off; label confirmed | **blocked on owner** (O5) |
| A9 | Font licences cover embedding Certia, Bounded, Editorial New **in an app binary** (O6, extended) | owner | Written confirmation | **blocked on owner** (O6) |
| A10 | App Review demo account on a paid plan; screenshots (6.9" iPhone, 13" iPad, Mac) | apple, owner | Uploaded | open |
| A11 | Submit for review; respond to findings | apple | "Ready for Sale" | open |
| A12 | CAPTCHA stays **off** for login/register while the app is live (a native client can't complete it) | owner | Admin setting confirmed off | open |
| A13 | Login limiter (6 per 10 min **per IP, including successes**) reviewed for mobile carriers behind shared IPs | api, owner | Decision recorded | open (P1) |
| A14 | Free plan allows one link (server counts every address against `custom_slugs_limit`; Overview says auto-generated addresses are unlimited) — roadmap #47 | api, owner | Random addresses don't count | open (P1; the app works, but Free is thin) |
| A15 | Strings exported to a String Catalog; English only at 1.0 | apple | `.xcstrings` in the project | open (P1) |
| A16 | Universal links (`card.site/…` opens the app) — needs `apple-app-site-association` on card.site | apple, infra | AASA served | P2 |
| A17 | Push notifications (lifecycle notices, traffic milestones) — no APNs support in the API | api, apple | — | P2 |
| A18 | Sign in with Apple + Google in the app — API needs native token exchange and Apple token revocation on deletion | api, apple | — | P2 |
| A19 | In-app purchase or US-only external purchase link (3.1.1 / 3.1.3) | owner | Decision | P2 (1.0 sells nothing) |
| A20 | Widgets (link traffic), App Intents ("Create short link"), Share extension (shorten from Safari) | apple | — | P2 |
| A21 | iPhone Duo layout and screenshots (required with the iOS 27.1 SDK) | apple | — | P2 (first update) |
| A22 | Bio page and file editing in the app | apple, web | — | P2 |

### Remaining steps to submission

In order, on a Mac with Xcode 27 and the Cardsite, Inc. developer account:

1. `brew install xcodegen && cd platform/apps/apple && xcodegen generate && open Cardsite.xcodeproj`
2. `cp Config/Signing.example.xcconfig Config/Signing.xcconfig`, set `DEVELOPMENT_TEAM`; confirm N1 (bundle ID) and N2 (API host).
3. Build `Cardsite` for an iPhone Simulator and for My Mac; fix what the compiler reports. Run tests (⌘U).
4. Run the stack (`make -C platform up`), point Debug at it, walk the device checklist on Simulator, then on devices against staging.
5. Create the App Store Connect record; paste `AppStore/metadata`, privacy label, age rating, review notes; create the demo account.
6. Product ▸ Archive for iOS and for macOS; upload; TestFlight internal test of the device checklist once more.
7. Capture screenshots; submit both platforms for review together.

**Fastest path to the main launch day:** steps 1–4 take about a day with a
Mac. Steps 5–7 take another day. Then review takes 1–2 days. If the main
launch is sooner than that, launch the web product on its day and the apps
when review passes. Apple's expedited review is for critical fixes and
events, so use it only if needed.

## 5. Owner decisions (native)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| N1 | Bundle ID (permanent) | `com.cardsite.app` · other | `com.cardsite.app` |
| N2 | Production API host for native | `https://cardsite.com` (Caddy passes `/api/*`) · `https://prod.cardsite.io` (openapi `servers`) | The host the web app calls in production; set in `Config/Release.xcconfig` |
| N3 | Apps on launch day or when review passes | Same day (needs steps 1–7 done ≥3 days before) · fast-follow | Fast-follow by days; don't hold the web launch |
| N4 | Purchasing in the app | None (1.0) · IAP · US external link | None at 1.0 (as built) |
| N5 | Free plan's single address (A14) | Fix #47 before app launch · ship as is | Fix #47: the app's default is a random address |
| N6 | Login rate limit for mobile (A13) | Count failures only · per account+IP · keep | Count failures only, per account + IP |

## 6. Android fast-follow (end of Q4)

See [`native-android.md`](native-android.md).
