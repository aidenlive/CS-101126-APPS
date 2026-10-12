# Cardsite for iPhone, iPad and Mac

One multiplatform SwiftUI app (iOS 18+, iPadOS 18+, macOS 15+) on the
Cardsite API and Studio Design. Launch plan, status and what is still
unverified: [`docs/launch/native-apple.md`](../../../docs/launch/native-apple.md).

## Run

The app needs the repository around it: StudioKit is a local package at
`platform/studio/packages/swift`, and the local API is `platform/`. With only
`platform/apps/apple` on disk, Xcode reports "Missing package product".

```sh
./scripts/doctor.sh                         # checks every path the project uses
brew install xcodegen                       # 2.42+
make -C ../.. up                            # local API on :8080 (Debug points here)
xcodegen generate && open Cardsite.xcodeproj
```

Needs Xcode 26 or later; Xcode 27 is current. For a device or an archive,
copy `Config/Signing.example.xcconfig` to `Config/Signing.xcconfig` and set
your team.

Tests: `swift test --package-path Packages/CardsiteKit` (or ⌘U in Xcode).

## Layout

| Path | What |
|---|---|
| `Cardsite/App` | Entry point, `AppModel` (session, configuration), `RootView`/`MainView` (tabs), menu commands |
| `Cardsite/Features/{Auth,Links,QRCodes,Pages,Account}` | One folder per tab: screens plus their `@Observable` models |
| `Cardsite/Shared` | `PagedListModel`, list and error states, platform seams (pasteboard, PNG, haptics) |
| `Cardsite/Resources` | Asset catalog (icons from `scripts/make-icons.mjs`), privacy manifest |
| `Cardsite/Supporting` | Info.plist, macOS entitlements |
| `Packages/CardsiteKit` | Platform-neutral core: models, `APIClient` actor, `APIError`, address and slug rules, token store. Tests decode live-captured fixtures |
| `ContractTests` | `native-contract.sh`: proves every request the app makes against a running API, and captures the fixtures |
| `Config` | xcconfigs: bundle ID, API host per configuration, signing |
| `AppStore` | Metadata, review notes, privacy label, age rating, screenshot plan |

## Rules this code keeps

- **The contract is what the server does.** Models follow `ContractTests/README.md`. Re-run the harness and `scripts/sync-fixtures.sh` when the API changes.
- **Studio only:** colours, type, spacing and radius come from StudioKit (`platform/studio/packages/swift`). The app hard-codes none. A missing component is requested from the `design` workstream, not drawn locally. The `.meta`, `.label` and `.kicker` styles are uppercase, so use them only for labels, never for sentences, emails or URLs.
- **Native chrome:** system `TabView`, `NavigationSplitView`, toolbars, sheets, menus. Liquid Glass comes from the system on bars, and content stays on opaque Studio surfaces.
- **Sells nothing, links to no purchase.** That is App Review 3.1.1 outside the US. The plan is shown read-only.
- **Every write sends `X-Requested-With`.** `APIClient` does it; don't build requests elsewhere.
- **A 401 on a password check is not a sign-out.** Requests that check the password use `credentialCheck: true`.
