# CardsiteUITests

XCUITest bundle for iPhone, iPad and Mac. It does two jobs:

- **`ScreenshotTests`** walks every main screen and attaches a screenshot of each.
- **`JourneyTests`** runs the device-checklist journeys: create a link, edit its destination, turn it off, make a QR code for it, and try to delete the account with a wrong password.

Neither needs a server. The app runs in **fixture mode**: `Cardsite/Debug/FixtureTransport.swift` answers every API call from an in-memory store seeded from the live-captured contract fixtures. That code is Debug-only.

## Run it locally

You need Xcode 26 or later (Xcode 27 is current) and XcodeGen.

```sh
cd platform/apps/apple
xcodegen generate

# iPhone, every screenshot pass and every journey
xcodebuild test -project Cardsite.xcodeproj -scheme Cardsite \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:CardsiteUITests -parallel-testing-enabled NO \
  -resultBundlePath /tmp/screens.xcresult

# Mac
xcodebuild test -project Cardsite.xcodeproj -scheme Cardsite \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CardsiteUITests -parallel-testing-enabled NO \
  -resultBundlePath /tmp/screens-mac.xcresult

# One pass or one journey only
#   -only-testing:CardsiteUITests/ScreenshotTests/testDark
#   -only-testing:CardsiteUITests/JourneyTests/testToggleDisabled

# PNGs, named after their attachments
python3 CardsiteUITests/ci/export-screens.py /tmp/screens.xcresult /tmp/screens/iphone
```

In Xcode, select the `Cardsite` scheme and press ⌘U. Or run a single test from the Test navigator. To open the result bundle, double-click the `.xcresult` file. The screenshots are under each test's attachments.

On a Mac, the first run asks for Accessibility and Automation permission for Xcode's test runner.

### Use fixture mode by hand

Edit Scheme → Run → Arguments, and add any of these launch arguments:

| Argument | Effect |
|---|---|
| `-CardsiteFixtures` | Signed in to a full fixture account. |
| `-CardsiteFixturesSignedOut` | Fixture mode, starting on the sign-in screen. |
| `-CardsiteFixturesEmpty` | Add this to either flag above for an account with nothing in it, to see empty states. |
| `-CardsiteFixtureLatency 1.5` | Delays every response, to see loading states. |
| `-AppleInterfaceStyle Dark` (or `Light`) | Sets the appearance. |
| `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` | Sets the text size. iOS honours this directly. On a Mac, `fixtureOverrides()` applies it. |

The fixture account:

- Avery Quinn, `avery@example.com`, on the Pro plan.
- The password is `cardsite-fixtures`. Any other password is wrong and gets the server's 401.
- The 2FA code is `123456`.
- Two workspaces: Personal, and Northwind Studio with 3 members.
- 8 short links:
  - the newest is `launch`, which has every setting: project, domain, splash page, pixel, targeting, password, UTM and cloaking;
  - `summer-sale` is off.
- 3 bio pages with blocks.
- One each of vCard, event, payment link, file and static page.
- 4 QR codes, 3 inbox items (2 unread), 3 uploads, form data, 2 API tokens and sign-in logs.

Creates, edits and deletes change the store for the rest of the launch. Every launch starts from the same seed.

## What the tests rely on

The tests find things by accessibility identifier first. If an identifier is missing, they fall back to visible labels, and they record the identifier as missing. Each test run attaches a `missing-identifiers-<platform>-<device>` text file. That file lists exactly what the app still needs.

| Identifier | On |
|---|---|
| `nav.<destination>` | The iPhone "More" row for a destination. Destinations: `home`, `links`, `statistics`, `qrCodes`, `pages`, `account`, `settings`, `workspace`, `inbox`, `uploads`. Sidebar items and tabs are system-drawn `Tab`s with no identifier: the harness finds them by title (`Destination.title` / `tabTitle`, which mirror `AppDestination`). |
| `screen.<destination>` | The root content of each destination. `DestinationView` stamps it for More/sidebar destinations; the four tab roots (Home, Links, Pages, QR Codes) stamp it on their primary content, because an identifier on a `NavigationStack`/`NavigationSplitView` doesn't surface. A destination also counts as open when its navigation title shows (navigation bar on iOS, window title on Mac), a marker only it has (`links.create`, `qr.create`, `pages.create`, `account.delete`) exists, or its sidebar row is selected. |
| `auth.signIn`, `auth.signUp` | The sign-in and sign-up forms. |
| `auth.toSignUp` | The "Create an account" button. |
| `links.row.<n>` | Rows of the Links list. `n` is 0 for the newest. |
| `links.create` | The new-link button. |
| `link.editor`, `link.editor.slug`, `link.editor.destination`, `link.editor.save` | The create-link sheet. |
| `link.detail` | The link detail root. |
| `link.detail.destination` | The destination text field. If the destination is edited in a sheet instead: `link.detail.changeDestination`, then `link.destination.field` and `link.destination.save`. |
| `link.detail.save` | The link's save button. Only if the form doesn't autosave. |
| `link.detail.enabled` | The on/off toggle. |
| `link.detail.qr` | "Create QR code" for this link. |
| `qr.row.<n>`, `qr.create` | The QR list and its new-QR button. |
| `qr.editor`, `qr.editor.name`, `qr.editor.url`, `qr.editor.save` | The QR builder. |
| `pages.row.<n>`, `page.editor` | The bio pages list and the page editor. |
| `account.delete` | The delete-account button. |
| `account.delete.password`, `account.delete.confirm`, `account.delete.error` | The delete-account sheet. |
| `nav.sidebar` | The iPad sidebar toggle, if the sidebar is collapsed. |

An identifier on a container works. The tests look inside it for the text field or switch.

## Screenshots

Each screenshot is named `<platform>-<device>-<appearance>-<textsize>-<screen>`, for example `ios-iphone17promax-dark-default-links` or `macos-mac-light-ax5-link-detail`.

- `platform` is `ios`, `ipados` or `macos`.
- `device` is the simulator name in lower case with only letters and digits.
- `textsize` is `default` or `ax5` (Accessibility XXXL).

The passes:

- `testLight`: light, default text.
- `testDark`: dark, default text.
- `testLargeText`: light, AX XXXL.
- `testEmptyStates`: light, on an empty account. These screens get the suffix `-empty`.

The screens:

- signed out: `sign-in`, `sign-up`;
- signed in: `home`, `links`, `link-detail`, `link-create`, `statistics`, `qr-codes`, `qr-builder`, `pages`, `page-editor`, `account`, `settings`, `workspace`, `inbox`, `uploads`.

The journeys also attach their end state, as `journey-*`.

Screens that follow on from each other share a launch: signed out (`sign-in`, `sign-up`); the top-level destinations; `links`, `link-create`, `link-detail`; `qr-codes`, `qr-builder`; `pages`, `page-editor`. The empty states are one launch. A screen that can't be reached from where the previous one left off is retried once on a fresh launch. If it still can't be reached, it is captured as `<screen>-unreached` and recorded as a failure, and the next screen starts on a fresh launch.

To add a screen, add a case to `ScreenshotTests.Screen`, put it in one of `ScreenshotTests.launches`, and add a branch to `show(_:in:)` (and to `tidy(after:in:)` if it leaves a sheet open).

## CI

The `.github/workflows/apple.yml` jobs:

- **`screens`** runs on `macos-26` for 3 devices:
  - the iPhone 17 Pro Max simulator, or the newest "Pro Max" available;
  - the iPad Pro 13-inch simulator, or the newest one available;
  - macOS.

  For each device it builds for testing, runs `CardsiteUITests`, and exports the PNGs with `xcresulttool export attachments`. Then it uploads the PNGs as the artifact `screens-<device>`.
  - The simulators get the 9:41 status bar.
  - On the Mac, the app is signed ad hoc with `Support/CI-macOS.entitlements`. Without a provisioning profile, macOS refuses `keychain-access-groups`, so that file leaves it out.
- **`screens-publish`** commits every device's PNGs to the orphan branch **`screens`**, under `runs/<sha>/<device>/`. Each run's `runs/<sha>/index.md` shows the screens as a grid, with a row per screen and a column per variant. The root `index.md` lists the 10 most recent runs. The branch is rewritten as one commit each time, so it stays small. To read it:

  ```sh
  git fetch origin screens && git checkout FETCH_HEAD -- runs/<sha>
  ```
- **`lint`** runs `scripts/lint-design.sh` if it exists.

When any build step fails, its `error:` lines go through `ci/annotate-errors.py`:

- The first errors become file and line annotations on the check run.
- The rest are packed into a few annotations: up to 200 lines.
- The same list goes to the job summary.

Test failures in `test.log` are annotated the same way.

| Script | What it does |
|---|---|
| `ci/pick-simulator.py "<name>" "<regex>"` | Chooses the simulator. It prints `udid=` and `name=`. |
| `ci/export-screens.py <xcresult> <dir>` | Exports the attachments and renames them. |
| `ci/publish-screens.py <dir>` | Writes to the `screens` branch. To try it against a local bare repository, set `SCREENS_REMOTE`. |
| `ci/annotate-errors.py <log> [max]` | Turns log errors into annotations. |
