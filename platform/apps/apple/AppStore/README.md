# App Store submission kit: Cardsite for Apple platforms

Everything App Store Connect asks for, ready to paste, plus what still has to
be produced on a Mac or by CI.

There is one app record with **universal purchase**. The iOS and iPadOS build
(with the Apple Watch app inside it), the macOS build and the visionOS build
share the bundle ID `com.cardsite.app` (owner decision N1). The widgets
(`.widgets`), the share extension (`.share`) and the watch app
(`.watchkitapp`) ship inside the app; they have no records of their own.

Nothing here has been checked against a compiled app: the app has never been
built (`docs/launch/native-apple.md`, A4 and A23).

| Item | Where | State |
|---|---|---|
| Name, subtitle, promotional text, keywords, description, URLs, release notes | `metadata/en-US/*.txt` | Updated 12 Oct to the full feature set. Lengths are within limits: name 8/30, subtitle 28/30, promotional text 146/170, keywords 100/100, description 2,430/4,000, release notes 519/4,000 |
| App icon (iOS light, dark and tinted; macOS 16–1024; visionOS solid image stack; watchOS) | `../Cardsite/Resources/Assets.xcassets`, `../CardsiteWatch/Assets.xcassets` | Generated from the Brand Kit mark by `../scripts/make-icons.mjs`. The light 1024 px icon is flattened (no alpha). Preview: `icon-preview.png` |
| Privacy manifest | `../Cardsite/Resources/PrivacyInfo.xcprivacy`, plus `../CardsiteWidgets/`, `../CardsiteShare/` and `../CardsiteWatch/PrivacyInfo.xcprivacy` | Updated 12 Oct: UserDefaults CA92.1 and 1C8F.1 in every bundle, Photos or Videos collected (app). The extension and watch manifests (A27) declare no tracking and no data beyond the app's; each is listed in its target's `project.yml` sources as a resource. Valid plists (`plistlib`); not yet checked by an App Store Connect upload |
| Privacy label answers | [Privacy label](#privacy-label) | Drafted. It must match the Privacy Policy, which is still **Draft** (launch gate G7) |
| Age rating answers | [Age rating](#age-rating) | Drafted |
| Review notes and demo account | [App Review notes](#app-review-notes) | Drafted. **The demo account must be created and seeded** |
| Screenshots | [Screenshots](#screenshots) | **Not produced.** CI captures iPhone, iPad and Mac once Actions billing is fixed (A23). Watch and visionOS are captured by hand |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in the app's Info.plist | Set (HTTPS through the OS only) |
| EU trader status (DSA) | App Store Connect → Business | **Owner**: the Cardsite, Inc. address, phone and email are published on the product page |
| Copyright | `© 2026 Cardsite, Inc.` | Set in Info.plist |
| Category | Productivity (secondary: Business) | Set in Info.plist (`LSApplicationCategoryType`) |

## App Review notes

Paste into App Store Connect → App Review Information → Notes:

> Cardsite® lets people create short web addresses (card.site/…), QR codes and bio pages, and see the traffic they receive. Accounts are shared with cardsite.com.
>
> **Demo account** (on a paid plan, seeded with links, pages, QR codes and a week of traffic):
> email: `appreview@cardsite.com` · password: in the Sign-In Information fields. Two-factor authentication is off on this account.
>
> **Where each feature is.** On iPhone, the tabs are Home, Links, Pages and QR, and everything else is under More. On iPad, Mac and Apple Vision Pro, everything is in the sidebar.
> • **Home:** the dashboard. Paste a URL into quick create to make a short link.
> • **Links:** tap + and enter any destination (for example apple.com), then Create. Open the link to edit its schedule, display rules, password, UTM tags and the other sections. Copy, Share and Card View are at the top. The "Live" switch turns the address off and on.
> • **Statistics:** in More or the sidebar, or "Full statistics" on any link.
> • **Pages:** open a bio page to edit its blocks (+ adds one), see the live preview, and change Page Settings.
> • **QR:** tap + and pick a type. The preview updates as you type. "One of my links" makes a code that follows the link. Share Image saves the code.
> • **Content** (vCards, payment links, events, splash pages, static pages, file links, uploads, data records), **Organise** (projects, domains, pixels) and **Account** (workspace, inbox, activity logs, account, preferences) are in More or the sidebar.
> • **Account:** Two-Factor Authentication, API Tokens, Change Password, and Delete Account.
> • **Widgets:** add "Link Traffic" or "My QR Code" from the widget gallery after signing in.
> • **Share extension:** in Safari, Share ▸ Cardsite shortens the current page.
> • **Siri and Shortcuts:** "Shorten a link with Cardsite", "Show my Cardsite QR code", "How many clicks in Cardsite".
> • **Apple Watch:** sign in on the iPhone first. The watch lists recent links, and a QR code opens full screen.
>
> **Purchasing:** the app sells nothing and contains no links or calls to action to buy anything. People on a paid plan bought it on cardsite.com. The app shows the plan's name read-only (guideline 3.1.3(b), multiplatform services). A feature the plan doesn't include says so, without an offer. "Payment links" and payment QR codes are links people make to *their own* checkout pages or payment details. The app processes no payments, and none goes to Cardsite.
>
> **Sign-in:** email and password only. There is no third-party or social login in the app, so guideline 4.8 does not apply.
>
> **Permissions:** the app asks only to *add* to Photos, when you save a QR code. Images to upload are chosen with the system photo picker, which needs no access. Add to Contacts and Add to Calendar use the system's own sheets, so the app never reads contacts or calendars.
>
> **Account deletion:** Account → Delete Account… deletes the account and all its content immediately, and cancels any web subscription (guideline 5.1.1(v)).
>
> **Free plan:** a new free account includes one custom address, so a second short link shows "Your plan includes 1 custom address…". That is expected behaviour, not an error. Please use the demo account above to try several.

Before submitting:

- Create the demo account on the production API.
- Put it on a paid plan that includes `password_protection` and premium blocks.
- Seed it with one of each link type, a bio page with several blocks, QR codes and real traffic.
- Leave 2FA off.

The free-plan note is there because the server counts every address against
`custom_slugs_limit` (roadmap #47). Remove it once auto-generated addresses
stop counting.

## Privacy label

In App Store Connect → App Privacy:

- **Data used to track you:** none. There is no tracking, no IDFA and no `NSPrivacyTrackingDomains`.
- **Data linked to you:**

| Data type | Collected because | Linked | Tracking |
|---|---|---|---|
| Contact Info → Name | Account profile | Yes | No |
| Contact Info → Email Address | Sign-in and the account email; inviting a workspace member by email | Yes | No |
| Identifiers → User ID | Account | Yes | No |
| User Content → Photos or Videos | Images the user uploads (Uploads, file links, bio page blocks) | Yes | No |
| User Content → Other User Content | Links, pages, QR codes, vCards, events, files and other resources the user creates | Yes | No |
| Location → Coarse Location | The server records the city of each sign-in (account security, Activity Logs) | Yes | No |

The purpose for all of these is **App Functionality**. There are no analytics,
advertising or third-party SDKs in the app, and no third-party AI (5.1.2(i)
does not apply; the AI tools are not in the app, N8).

**What the app touches on the device, and why it isn't collection:**

- **Contacts and Calendar** are used only through system UI. Add to Contacts presents `CNContactViewController` and Add to Calendar presents `EKEventEditViewController`. Both run out of process: the person confirms the save there, and the app never reads, or asks for access to, contacts or calendars. The vCard or event data comes from the user's own Cardsite resource. `NSContactsUsageDescription` is present only as a safeguard.
- **Photos** is add-only. `NSPhotoLibraryAddUsageDescription` covers saving a QR code image. Uploads use `PhotosPicker`, which hands the app only the images the person picks, with no library access. Those uploaded images are the "Photos or Videos" row above.
- **Files** come from the system file importer and are uploaded only when the person picks them (up to 10 MB).
- **Local storage** holds the session token in the Keychain. The selected workspace and UI state are in `UserDefaults`. The App Group holds the session context and cached QR code images for the widgets and the share extension. On Apple Watch, the session sent from the iPhone sits in the watch's keychain and defaults. None of it leaves the device except to the Cardsite API.

If the Privacy Policy, once approved by counsel (O5), says more or less than
this, the label and every `PrivacyInfo.xcprivacy` change with it.

Visitor analytics on card.site addresses are data about *visitors to the
user's links*, not about the app user. The Privacy Policy covers them, not
this label; confirm with counsel.

## Age rating

Answer **None** to every content question (violence, sexual content,
profanity, drugs, gambling, horror, medical). Then:

- Unrestricted web access: **No**. Links open in the person's browser. The bio page preview is a `WKWebView` that shows only the person's own page.
- User-generated content: **Yes**. Users create addresses and pages that others can open. Cardsite's Acceptable Use Policy and abuse reporting apply (marketing `legal/acceptable-use`, Draft).
- Messaging or chat between users: **No**. Workspace members share resources, but there is no messaging. Social features (profiles, following): **No**.
- Age assurance and parental controls: **No**.

Expected result: **13+** under the 2026 questionnaire, because of
user-generated content. Confirm in App Store Connect; the questionnaire
computes it.

## Screenshots

Every set: 1–10 PNG or JPEG images, no transparency, the same size within a
set. Use a seeded demo account with realistic names and a week of traffic.
The CI fixture account (Avery Quinn, Pro plan, two workspaces) is realistic
enough. Shoot light appearance first.

| Device | Size (pixels) | Required | Shots | Source |
|---|---|---|---|---|
| iPhone 6.9" | 1320 × 2868 portrait | Yes | 1 Home dashboard · 2 Link editor (schedule and display rules) · 3 Statistics with breakdowns · 4 Bio page block editor · 5 QR builder with preview · 6 Widgets on the Home Screen · 7 Share extension over Safari | CI `screens` (iPhone 17 Pro Max), 1–5; 6–7 by hand on the Simulator |
| iPad 13" | 2064 × 2752 portrait (or 2752 × 2064) | Yes (the app runs on iPad) | 1 Links split view with the editor · 2 Page editor with preview · 3 QR builder side by side · 4 ⌘K palette · 5 Statistics | CI `screens` (iPad Pro 13-inch) |
| Mac | 2880 × 1800 (16:10) | Yes | 1 Home with sidebar · 2 Link editor · 3 Page editor with preview · 4 QR builder · 5 Settings window | CI `screens` (Mac). The window captures need placing on a 2880 × 1800 canvas |
| Apple Vision Pro | 3840 × 2160 | Yes (visionOS destination) | 1 Home window · 2 Link editor · 3 QR builder | By hand: visionOS Simulator, File ▸ Save Screen. Not in CI |
| Apple Watch | 422 × 514 (Ultra 3 and Ultra 4); any one listed size is enough | Yes (the iOS app contains a watch app) | 1 Recent links · 2 A link's day and week · 3 Full-screen QR code | By hand: watchOS Simulator. Not in CI |
| iPhone Duo (foldable) | Outer 1398 × 2034, inner 2007 × 2853 (portrait; landscape also accepted) | **Only for builds made with the iOS 27.1 SDK or later, from April 2027.** Optional before then | The iPhone set, inner display first | Needs the Duo layout (A24); plan it for the first update built with Xcode 27.1 |

Notes:

- CI writes every capture to the `screens` branch under `runs/<sha>/`. The simulator status bar is set to App Store style (9:41, full signal and battery). The screens are of the in-app fixture server, so they need no network.
- A 1.0 built with the iOS 27.0 SDK doesn't need Duo screenshots. If 1.0 is built with Xcode 27.1 after April 2027, it does.
- App Previews (video) are optional and not planned for 1.0.
