# Cardsite for iPhone, iPad, Mac, Apple Vision Pro and Apple Watch

This folder holds one multiplatform SwiftUI app (iOS 18+, iPadOS 18+, macOS
15+, visionOS 2+) on the Cardsite® API and Studio Design. It ships with:

- widgets and a share extension (iOS and macOS);
- App Intents;
- an Apple Watch companion (watchOS 11+).

**Nothing here has been compiled yet.** The launch plan, the status and what
is still unverified are in
[`docs/launch/native-apple.md`](../../../docs/launch/native-apple.md).

## Run

The app needs the repository around it, because StudioKit is a local package
at `platform/studio/packages/swift`. With only `platform/apps/apple` on disk,
Xcode reports "Missing package product".

```sh
./scripts/doctor.sh                         # checks every path the project uses
brew install xcodegen                       # 2.42+ (multi-destination targets)
xcodegen generate && open Cardsite.xcodeproj
```

You need Xcode 26 or later; Xcode 27 is current. Use the `Cardsite` scheme for
the iPhone, iPad, Mac and Vision Pro app, and `CardsiteWatch` for the watch
app on its own.

- **Without a server:** add the launch argument `-CardsiteFixtures` (Debug only) to run against the in-app fixture server. See [`CardsiteUITests/README.md`](CardsiteUITests/README.md).
- **Against a local API:** run the API from CS-CORE (`make -C platform up`, port 8080). Debug points there.
- **On a device or for an archive:** copy `Config/Signing.example.xcconfig` to `Config/Signing.xcconfig` and set your team.

The widgets, the share extension, the intents and the watch only share the
session in a signed build that has the App Group and keychain group
provisioned (`native-apple.md` A25).

Tests: `swift test --package-path Packages/CardsiteKit`, or ⌘U in Xcode, which
also runs the UI tests.

## Layout

| Path | What |
|---|---|
| `Cardsite/App` | Entry point, `AppModel` (session, workspace, deep links, sharing with the extensions and the watch), `RootView`/`MainView` (tabs and sidebar), `Destinations.swift` (the navigation registry), menu commands |
| `Cardsite/Features/*` | One folder per area, holding its screens and their `@Observable` models: Auth, Home, Search, Links, Statistics, ResourceEditor (shared editor sections), Resources (vCard, event, payment, file, static, splash), Pages (block editor, settings), QRCodes (builder), Organise (projects, domains, pixels), Library (uploads, data, logs), Workspace, Inbox, Account |
| `Cardsite/Intents` | App Intents and App Shortcuts. `Intents/Shared` is compiled into the widgets too |
| `Cardsite/Shared` | List and error states, shared rows and glyphs, the workspace switcher, platform seams (pasteboard, PNG, haptics) |
| `Cardsite/Debug` | The fixture server for UI tests and screenshots (Debug only) |
| `Cardsite/Resources` | Asset catalog (icons from `scripts/make-icons.mjs`), privacy manifest |
| `Cardsite/Supporting` | Info.plist, entitlements |
| `CardsiteWidgets` | Link Traffic and My QR Code widgets |
| `CardsiteShare` | The "Shorten with Cardsite" share extension |
| `CardsiteWatch` | The watchOS companion (recent links, full-screen QR code) |
| `CardsiteUITests` | Screenshot passes and journey tests, plus the CI helpers in `ci/` |
| `Packages/CardsiteKit` | The platform-neutral core: models, the `APIClient` actor split by domain, `APIError`, address and slug rules, the token store, `SharedSession`. Tests decode live-captured fixtures |
| `ContractTests` | `native-contract.sh`, which proves every request the app makes against a running API and captures the fixtures |
| `Config` | xcconfigs: bundle ID, API host per configuration, signing |
| `AppStore` | Metadata, review notes, privacy label, age rating, screenshot plan |
| `scripts` | `doctor.sh`, `lint-design.sh` (the Studio design lint), `sync-fixtures.sh`, `make-icons.mjs` |

## Rules this code keeps

- **The contract is what the server does.** Models follow `ContractTests/README.md`. Re-run the harness and `scripts/sync-fixtures.sh` when the API changes.
- **Studio only.** Colours, type, spacing and radius come from StudioKit, and `scripts/lint-design.sh` fails on literals. A missing component is requested from the design workstream, not drawn locally. The `.meta`, `.label` and `.kicker` styles are uppercase, so use them only for labels, never for sentences, emails or URLs.
- **Native chrome.** Use system `TabView`, `NavigationSplitView`, toolbars, sheets, menus and `Form`. Liquid Glass comes from the system on bars, and content stays on opaque Studio surfaces.
- **Sells nothing, links to no purchase.** That is App Review 3.1.1 outside the US. The plan is shown read-only.
- **Every write sends `X-Requested-With`.** `APIClient` does it; don't build requests elsewhere.
- **A 401 on a password check is not a sign-out.** Requests that check the password use `credentialCheck: true`.
