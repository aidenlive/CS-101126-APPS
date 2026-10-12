# Apple platform reference — October 2026

> Research for the Cardsite Apple launch, 11 Oct 2026. Official Apple sources first; every claim is labelled RELEASED / BETA / ANNOUNCED / UNVERIFIED and cited. Re-verify version numbers and dates against the linked Apple pages before relying on them. Used by `.claude/agents/apple-native.md` and [`native-apple.md`](native-apple.md).


Labels: **RELEASED** (shipped publicly or in force), **BETA** (developer or public beta / RC), **ANNOUNCED** (Apple has dated it but it is not yet in force), **UNVERIFIED** (third-party only, unconfirmed or conflicting).
Method: WebSearch/WebFetch. Official Apple sources were used where they could be fetched. HIG HTML pages need JavaScript, so HIG text came from the HIG JSON data endpoint and the "Adopting Liquid Glass" doc in .md form. Every claim has a source number; see the Sources section.

---

## 1. OS, Xcode and Swift versions

| Item | Status | Detail | Src |
|---|---|---|---|
| iOS / iPadOS 27.0 | RELEASED | Public release Mon 14 Sep 2026 (15 Sep in Japan time). Supports the same iPhones as iOS 26 (iPhone 11 and later, SE 2nd gen and later). | [3][4][5] |
| macOS 27 "Golden Gate" | RELEASED | Released 14 Sep 2026. **Apple silicon only.** | [3][6][2] |
| watchOS / tvOS / visionOS 27 | RELEASED | 14 Sep 2026 | [3][5] |
| iOS / iPadOS 27.0.1 (24A446), macOS 27.0.1 (26A434) | RELEASED | 28 Sep 2026. These are the **current shipping versions**. | [5][7] |
| iOS / iPadOS / macOS 27.1 | BETA / ANNOUNCED | Xcode 27.1 RC (27A9275) came out 5 Oct 2026. iPhone Duo (foldable) ships on iOS 27.1, available 23 Oct 2026. | [5][2] |
| iOS / iPadOS / macOS 27.2 | BETA | beta 3 on 5 Oct 2026. Xcode 27.2 beta 2 (27B5028f) on 28 Sep. | [5][1] |
| iOS 26.x line | RELEASED | Still receiving updates: iOS 26.7 (security), iPadOS 26.7.1 on 28 Sep 2026. | [5][4] |
| **Xcode 27.0 (27A266a)** | RELEASED | 14 Sep 2026. Includes **Swift 6.4** and the OS 27 SDKs. **Requires macOS Tahoe 26.6+ and only installs on Apple silicon Macs.** iOS deployment targets 15–27. On-device debugging needs iOS 17+. | [5][8][1] |
| **Swift 6.4** | RELEASED | Announced on swift.org 15 Sep 2026. Notable changes: `await` allowed in `defer`, `withTaskCancellationShield`, more noncopyable support (`UniqueArray`, `UniqueBox`), `Iterable`, borrow/mutate accessors with `Span` / `InlineArray`, `@diagnose`, `Module::` qualification, Swift Build as the default, Subprocess 1.0. | [9][10] |
| Swift language modes | RELEASED | Xcode 27 supports language modes 6, 5, 4.2 and 4. | [1] |

Answer: **iOS / iPadOS / macOS 27 shipped publicly on 14 Sep 2026.** The current versions are 27.0.1, and 27.1 is about to ship (RC). WWDC26 was 8 Jun 2026 [2].

## 2. App Store Connect SDK and deployment requirements

| Requirement | Status | Date | Src |
|---|---|---|---|
| Uploads must be built with **Xcode 26+ using the iOS/iPadOS/tvOS/visionOS/watchOS 26 SDK** | RELEASED (in force) | since **28 Apr 2026** | [11] |
| iOS/iPadOS apps must **target iOS 13 or later** | RELEASED (listed as "Since September 9, 2026") | 9 Sep 2026 | [11] |
| Uploads must be built with the **iOS/iPadOS 27 SDK (Xcode 27) or later, and target iOS 15 or later**. tvOS, visionOS and watchOS 27 SDKs required too. | ANNOUNCED | **April 2027** (no exact day given) | [12][2] |
| iPhone Duo screenshots required for apps built with the iOS 27.1 SDK or later | ANNOUNCED | April 2027 | [2][13] |
| Submissions with the OS 27 SDKs are accepted | RELEASED | opened 9 Sep 2026 (Xcode 27 RC) | [2] |
| **Launch screen required:** apps built with the iOS 27.0 SDK must have `UILaunchScreen`, `UILaunchScreens`, `UILaunchStoryboardName` or `UILaunchStoryboards` in Info.plist, or they are **rejected** | RELEASED (applies when you build with SDK 27) | — | [14] |
| **UIScene life cycle required:** apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch. SwiftUI `App` already does this. | RELEASED | — | [14] |
| macOS 27 apps: arm64 only. With a macOS 27.0 deployment target, `ARCHS_STANDARD` drops x86_64. The macOS 27 SDK can still back-deploy Universal builds to macOS 12+. | RELEASED | — | [8][2] |
| Remove the `com.apple.quarantine` xattr from macOS app files before upload | RELEASED | since 18 Feb 2025 | [11] |

Recommendation: build a new app with **Xcode 27** (27.1 once it is final) now. Xcode 26 builds are still accepted until April 2027, but Xcode 27 is required from then on.

Conflict (UNVERIFIED): the news feed's "target iOS 13 or later" line [11] and the submitting page's "target iOS 15 or later starting April 2027" [12] are different milestones. Either way, a new app targeting iOS 18 or iOS 26+ is unaffected.

## 3. Liquid Glass and design language

### HIG and official guidance (RELEASED)
- **Glass is for controls and navigation, not content.** "Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer." HIG Materials says **"Don't use Liquid Glass in the content layer"**. The exception is transient controls such as sliders and toggles, which turn to glass while someone is using them. [15]
- **Use glass sparingly.** "If you apply Liquid Glass effects to a custom control, do so sparingly… Limit these effects to the most important functional elements." [15][16]
- **Variants.** `Glass.regular` blurs and adjusts luminosity; use it for text-heavy components such as alerts, sidebars and popovers. `Glass.clear` is highly translucent and meant only for components over visually rich media; add a dark dimming layer at about 35% opacity when the content underneath is bright. [15]
- HIG Materials change log: "Added guidance for Liquid Glass" on 9 Jun 2025 and "Updated guidance" on 9 Sep 2025. The JSON fetched showed no iOS 27 entry on the Materials page. [15]
- Apple published iOS/iPadOS/macOS 27 design kits on 23 Jun 2026 "with Liquid Glass updates and Dark Mode for macOS". [2]

### Key SwiftUI APIs (from "Adopting Liquid Glass" and SwiftUI updates) [16][17]
- Standard components adopt Liquid Glass automatically: `NavigationStack`, `NavigationSplitView`, `.toolbar`, `TabView`, sheets, popovers, menus. **Remove custom backgrounds** on bars, split views and toolbars.
- Custom glass: `.glassEffect(_:in:)`; group shapes in `GlassEffectContainer` for performance and morphing; `.buttonStyle(.glass)`, `.glassProminent` and `.glass(_:)`.
- Toolbars: `ToolbarSpacer` (`.fixed`) to group items; hide a whole item with `ToolbarContent.hidden(_:)`. **iOS 27 adds** `visibilityPriority(_:)`, `ToolbarOverflowMenu`, `.topBarPinnedTrailing`, `toolbarMinimizationBehavior(_:for:)` (replaces `toolbarMinimizeBehavior`), `toolbarColorScheme(_, for: .statusBar)` and `toolbarVisibility(_, for: .statusBar)`.
- Tab bar: `.tabViewStyle(.sidebarAdaptable)` turns the tab bar into a sidebar on iPad and Mac; `.tabBarMinimizeBehavior(.onScrollDown)`; `Tab(role: .search)`; `TabViewBottomAccessoryPlacement`. **iOS 27 adds** `TabRole.prominent` for a separate trailing tab, and `TabView` may **crash if its selection is set to a hidden or unavailable tab** (SDK 27). [14][17]
- Sidebars and split views: `NavigationSplitView` plus `.inspector`; `.backgroundExtensionEffect()` extends hero imagery under the sidebar; `safeAreaBar` and `scrollEdgeEffectStyle` for custom bars; `ConcentricRectangle` and `.rect(corners:isUniform:)` for concentric corners. **iOS 27:** `GeometryProxy.concentricCornerRadii`. [16][14]
- **New in iOS 27 / September 2026 (iPhone Duo):** `ArrangementView` with `.split` and `.overlay` styles, `ReservedRegion` (hinge and camera), `onHingeChange`, vertical-axis toolbar APIs (`toolbarVerticalEdge`, `toolbarVerticalBehavior`, `axisBehavior`). [17]
- Menus in iPadOS/macOS 27: SwiftUI now **hides most menu-item symbol images by default**. Use `.labelStyle(.titleAndIcon)` where an icon represents an object. [14]
- Text fields: `.roundedBorder` and `.squareBorder` are soft-deprecated; use `.bordered` and `textInputBorderShape(_:)`. [14]

### UIDesignRequiresCompatibility
- **Status: effectively removed for SDK 27 (RELEASED).** Apple's doc reads: "The system ignores this key when you build for iOS 27 or later, iPadOS 27 or later, Mac Catalyst 27 or later, macOS 27 or later, or tvOS 27 or later." [18] The key still works for builds made with the 26 SDK (Xcode 26), but that route closes in April 2027. A new app should adopt Liquid Glass from day one. Apple did not answer the forum clarification thread. [19]

## 4. Submission requirements that can block a new app

| Area | Status | Requirement | Src |
|---|---|---|---|
| Privacy manifest / required-reason APIs | RELEASED (since 1 May 2024) | Apps that use required-reason APIs (file timestamp, system boot time, disk space, active keyboards, UserDefaults) without declaring `NSPrivacyAccessedAPITypes` reasons in `PrivacyInfo.xcprivacy` "aren't accepted by App Store Connect". Each SDK bundle needs its own manifest. | [20][11] |
| Privacy Nutrition Label | RELEASED | App privacy details in ASC, including third-party SDK practices, are "required in order to submit new apps and app updates". 5.1.2(i) now names **third-party AI**: disclose and get explicit permission before sharing personal data. | [12][21] |
| Accessibility Nutrition Label | RELEASED (recommended, not blocking) | Declare VoiceOver, Larger Text and similar support per platform. | [12] |
| Account deletion 5.1.1(v) | RELEASED | "If your app supports account creation, you must also offer account deletion within the app." | [21] |
| Sign in with Apple / 4.8 | RELEASED | If a third-party or social login sets up the primary account, you must also offer an equivalent login that limits data to name and email, allows email hiding, and doesn't track without consent. Sign in with Apple qualifies; the guideline text doesn't require it by name. Listed exceptions: your own account system only, enterprise/education accounts, government eID, and clients for a specific third-party service. | [21] |
| SIWA relay domain | RELEASED | New private-relay addresses use `private.icloud.com` (24 Aug 2026). Update email validation and allowlists. | [2] |
| 4.2 Minimum functionality | RELEASED | "Your app should include features, content, and UI that elevate it beyond a repackaged website." 4.2.2 bans apps that are mainly marketing, web clippings or collections of links. **4.3(a)/(b) spam** guidance was clarified on 8 Jun 2026. | [21][22] |
| 3.1.1 IAP for digital goods | RELEASED | Unlocking features or content (subscriptions, premium content and so on) must use IAP; no license keys, QR codes and the like. | [21] |
| **US external purchase links** | RELEASED (US storefront only) | 3.1.1(a) and 3.1.3(a): entitlements "are not required for developers to include buttons, external links, or other calls to action in their United States storefront apps". In all other storefronts the anti-steering ban still applies. Apple has **not charged commission on US link-outs** since the April 2025 contempt order. The Ninth Circuit upheld that order in Dec 2025; SCOTUS denied a stay on 6 May 2026 and **granted cert on 30 Jun 2026 (No. 25-1311)**. Apple's merits brief was filed 14 Sep 2026 and Epic's is due 13 Nov 2026. A future commission is possible, depending on remand or the SCOTUS outcome. | [21][23][24][25] |
| EU terms | RELEASED | From 1 Oct 2026 the Core Technology Fee becomes a 5% Core Technology Commission, applies to alternative terms (Attachment 14). | [2] |
| Subscriptions | ANNOUNCED / RELEASED | StoreKit 2 required for Bundles & Suites (later in 2026). Multiseat purchasing is on by default; Volume Purchasing launches 22 Oct 2026. | [2] |
| **Age rating questionnaire** | RELEASED | New questionnaire (ratings 4+/9+/13+/16+/18+; sections for In-App Controls, Capabilities, Medical/Wellness and others). Answers were due **31 Jan 2026** to avoid submission interruption. **Social-media questions were added 9 Jul 2026 and became required September 2026**; they add a Social Media descriptor and the Social Media Time Allowance. Korea: GRAC override, and two descriptors move to 12+ in Oct 2026. Texas SB 2420 has been in effect since 4 Jun 2026; use the Declared Age Range API. | [11][2][26] |
| Review guidelines update | RELEASED | 8 Jun 2026: revised kid/teen safety intro, 1.2 developer responsibility, 4.3(a)/(b), 4.5.3 (Live Activities spam). | [22] |
| **EU DSA trader status** | RELEASED | Required for EU distribution: since 16 Oct 2024 for updates and since 17 Feb 2025 apps without it are removed from the EU store. Traders must publish a verified address, phone and email. | [11][27] |
| **Export compliance** | RELEASED | Set `ITSAppUsesNonExemptEncryption` = `NO` in Info.plist if you use only exempt or OS crypto (for example HTTPS via URLSession) to skip the questionnaire. Proprietary crypto needs documentation and `ITSEncryptionExportComplianceCode`. Exempt users may still owe the BIS annual self-classification report. | [28] |
| **Screenshots** | RELEASED | **iPhone:** 6.9" (1320×2868, 1290×2796 or 1260×2736) **or** 6.5" (1284×2778 / 1242×2688). 6.5" is required only if 6.9" isn't provided, so providing 6.9" covers it. **iPad 13"** (2064×2752 or 2048×2732) required if the app runs on iPad. **Mac** 16:10 (1280×800, 1440×900, 2560×1600 or 2880×1800) required for Mac apps. 1–10 per size, JPEG/PNG, no alpha. iPhone Duo (outer 1398×2034, inner 2007×2853) is optional now and required April 2027 for iOS 27.1 SDK+. | [13][2] |
| New creative assets | RELEASED (optional) | 5 Oct 2026: product page headers, search-result assets, ASC preview tool and Asset Library. | [2] |

## 5. Swift 6.x / SwiftUI recommendations

- **Observation (RELEASED):** use `@Observable` (iOS 17+), not `ObservableObject`. The framework now includes the `Observations` async sequence and `withContinuousObservation`. [29]
- **New `@State` macro (Xcode 27, RELEASED):** `@State private var model = Model()` now initializes once (back-deploys to iOS 17-aligned OSes). Breaking cases: you can't assign in `init` when an initial value is declared, and the synthesized private memberwise init is disabled. [14][17]
- **Concurrency defaults (RELEASED):** Swift 6.2 / Xcode 26 introduced Approachable Concurrency. New Xcode 26 projects default to **Default Actor Isolation = MainActor**; existing projects stay `nonisolated`. Use `@concurrent` for work that must run off the main actor. Apple's SDK 27 notes confirm that under approachable-concurrency defaults an unannotated `nonisolated` async method runs on the main actor, so use `@concurrent` instead. `#Preview` bodies now run on the main actor (Xcode 27). [9][30][14][8]
  - UNVERIFIED: whether Xcode 27 templates change these defaults further. Nothing found in the Xcode 27 notes.
- **Navigation:** `NavigationSplitView` (sidebar → content → detail with `columnVisibility` / `preferredCompactColumn`) plus `.inspector` for iPad and Mac; `TabView` + `.sidebarAdaptable` for tab-first apps. Both scale to continuous iPad window resizing. On iOS 27 SDK, iPad apps are treated as resizable regardless of `UISupportedInterfaceOrientations`. [16][14]
- **New 2026 SwiftUI APIs (RELEASED, iOS 27):** `ContentBuilder` (unified builder), `reorderable()` / `reorderContainer`, generalized `swipeActions` + `swipeActionsContainer`, `NavigationTransition.crossFade`, `AsyncImage` HTTP caching + `asyncImageURLSession`, `alert(error:)` / `alert(_:item:)` (back-deploy to iOS 15), the `Document` / `ReadableDocument` / `WritableDocument` model (`FileDocument` deprecated), `TabsPickerStyle`, gesture input-kind filtering, interactive `Text` selection, `ArrangementView`, `ReservedRegion`, hinge APIs. [17][14]
- **Deprecations to avoid:** `canOpenURL:` (deprecated in iOS 27), On Demand Resources (use Background Assets), `ImageCreator` (stops working in OS 27; use Image Playground), `FileDocument` / `ReferenceFileDocument`. [14][8][2]

## 6. App Review turnaround

- **Apple (official, RELEASED):** "App Review works around the clock, typically reviewing at least 50% of submissions in less than 24 hours and 90% in less than 48 hours." Expedited review is available for critical bugs and event deadlines. [31]
  - UNVERIFIED conflict: a third-party page claims Apple says "90% … in less than 24 hours" [32]. The Apple page fetched directly says 50% / 24h and 90% / 48h.
- **Third-party measurement (UNVERIFIED, Runway data via Choicely):** average waiting-for-review in Sep 2026 was about 7h, plus about 2h 21m in review; monthly 2026 averages ranged 6h to 14.5h; Mondays and Tuesdays were slowest. [32] Forum threads still report individual multi-day or multi-week "Waiting for Review" outliers. [33]
- Plan for 24–48h on a first submission and add buffer for rejections. First-time apps get more scrutiny (general expectation, UNVERIFIED).

---

## Sources
1. Xcode system requirements, developer.apple.com: https://developer.apple.com/xcode/system-requirements/
2. Apple Developer News (Jun–Oct 2026 items): https://developer.apple.com/news/
3. MacRumors, "Apple Announces iOS 27 Release Date" (9 Sep 2026): https://macrumors.com/2026/09/09/apple-announces-ios-27-release-date/
4. Classmethod weekly changes (18 Sep 2026): https://dev.classmethod.jp/en/articles/ios-dev-weekly-changes-20260918/
5. Apple Developer Releases: https://developer.apple.com/news/releases/
6. Eclectic Light, macOS Golden Gate released (14 Sep 2026): https://eclecticlight.co/2026/09/14/apple-has-released-macos-golden-gate-and-security-updates-to-tahoe-26-7-sequoia-15-8/
7. MacRumors, macOS Golden Gate 27.0.1: https://macrumors.com/2026/09/28/apple-releases-macos-27-0-1 ; iPhone in Canada, iOS 27.0.1: https://www.iphoneincanada.ca/2026/09/28/you-can-now-download-ios-27-0-1-for-iphone-and-more/
8. Xcode 27 Release Notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
9. Swift.org blog (Swift 6.4 Released, 15 Sep 2026; Swift 6.2 post): https://www.swift.org/blog/ ; https://www.swift.org/blog/swift-6.2-released/
10. InfoQ, Swift 6.4 released: https://www.infoq.com/news/2026/09/swift-6-4-released/
11. Apple Upcoming Requirements: https://developer.apple.com/news/upcoming-requirements/
12. Apple, Submitting to the App Store: https://developer.apple.com/app-store/submitting/
13. Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
14. iOS & iPadOS 27 Release Notes: https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
15. HIG Materials (JSON data endpoint): https://developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.json (page: https://developer.apple.com/design/human-interface-guidelines/materials)
16. Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
17. SwiftUI updates: https://developer.apple.com/documentation/updates/swiftui
18. UIDesignRequiresCompatibility: https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
19. Apple Developer Forums thread 832543: https://developer.apple.com/forums/thread/832543
20. Describing use of required reason API: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
21. App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
22. Apple News, updated guidelines (8 Jun 2026): https://developer.apple.com/news/?id=a233fmpw
23. The Next Web, SCOTUS stay denial (6 May 2026): https://thenextweb.com/news/supreme-court-apple-epic-contempt-stay-denial
24. SCOTUSblog, Apple v. Epic (No. 25-1311): https://www.scotusblog.com/cases/apple-inc-v-epic-games-inc-2/
25. TechSpot (1 Jul 2026): https://www.techspot.com/news/112956-apple-fight-epic-over-app-store-fees-reaches.html ; IPWatchdog cert grant: https://ipwatchdog.com/2026/06/30/high-court-grants-cert-in-apples-challenge-to-ninth-circuit-contempt-ruling-in-app-store-dispute/
26. Age ratings values and definitions: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/
27. DSA trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
28. Complying with Encryption Export Regulations: https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
29. Observation framework: https://developer.apple.com/documentation/observation
30. Donny Wals, Default actor isolation in Xcode 26: https://www.donnywals.com/setting-default-actor-isolation-in-xcode-26/
31. Apple, App Review (distribute): https://developer.apple.com/distribute/app-review/
32. Choicely, App Review times 2026: https://www.choicely.com/tutorials/how-long-does-app-review-take
33. Apple Developer Forums, waiting-for-review thread: https://developer.apple.com/forums/thread/849518
