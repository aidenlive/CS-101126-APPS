# App Store submission kit — Cardsite for iPhone, iPad and Mac

Everything App Store Connect asks for, ready to paste, plus what still has to
be produced on a Mac. One app record, **universal purchase**: the iOS/iPadOS
and macOS builds share the bundle ID `com.cardsite.app` (owner decision N1).

| Item | Where | State |
|---|---|---|
| Name, subtitle, promo text, keywords, description, URLs, release notes | `metadata/en-US/*.txt` | Drafted; lengths within limits (name 8/30, subtitle 28/30, promo 139/170, keywords 98/100) |
| App icon (iOS light/dark/tinted, macOS 16–1024) | `../Cardsite/Resources/Assets.xcassets/AppIcon.appiconset` | Generated from the Brand Kit mark by `../scripts/make-icons.mjs`; light icon flattened (no alpha). Preview: `icon-preview.png` |
| Privacy manifest | `../Cardsite/Resources/PrivacyInfo.xcprivacy` | Written |
| Privacy label answers | [Privacy label](#privacy-label) | Drafted; must match the Privacy Policy, which is still **Draft** (launch gate G7) |
| Age rating answers | [Age rating](#age-rating) | Drafted |
| Review notes + demo account | [App Review notes](#app-review-notes) | Drafted; **demo account must be created** |
| Screenshots | [Screenshots](#screenshots) | **Not produced** — needs the app running on a Mac |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in Info.plist | Set (HTTPS via the OS only) |
| EU trader status (DSA) | App Store Connect → Business | **Owner**: Cardsite, Inc. address, phone, email are published on the product page |
| Copyright | `© 2026 Cardsite, Inc.` | Set in Info.plist |
| Category | Productivity (secondary: Business) | Set in Info.plist (`LSApplicationCategoryType`) |

## App Review notes

Paste into App Store Connect → App Review Information → Notes:

> Cardsite lets people create short web addresses (card.site/…) and QR codes, see the traffic they receive, and share their bio pages. Accounts are shared with cardsite.com.
>
> **Demo account** (on a paid plan, so creating several links is possible):
> email: `appreview@cardsite.com` · password: provided in the Sign-In Information fields.
>
> **Things to try:** Links tab → + → enter any destination (e.g. apple.com) → Create. Open the link → Copy / Share / View Card; toggle "Address is live"; change the destination. QR Codes tab → + → "One of my links" → Create → Share Image. Account tab → Delete Account (requires the password; permanent).
>
> **Purchasing:** the app sells nothing and contains no links or calls to action to buy elsewhere. Users on a paid plan bought it on cardsite.com; the app shows the plan name only (guideline 3.1.3(b), multiplatform services).
>
> **Sign-in:** email and password only — no third-party or social login in the app (guideline 4.8 does not apply).
>
> **Account deletion:** Account → Delete Account… deletes the account and all its content immediately and cancels any web subscription (guideline 5.1.1(v)).
>
> **Free plan:** a new free account includes one custom address, so a second short link shows "Your plan includes 1 custom address…" — expected behaviour, not an error. Please use the demo account above to try several.

The free-plan note exists because the server counts every address against
`custom_slugs_limit` (roadmap #47); remove it once auto-generated addresses
stop counting.

## Privacy label

App Store Connect → App Privacy. **Data used to track you: none.**
**Data linked to you:**

| Data type | Collected because | Linked | Tracking |
|---|---|---|---|
| Contact Info → Name | Account profile | Yes | No |
| Contact Info → Email Address | Sign-in, account email | Yes | No |
| Identifiers → User ID | Account | Yes | No |
| User Content → Other User Content | Links, QR codes, pages the user creates | Yes | No |
| Location → Coarse Location | Server records the city of each sign-in (account security) | Yes | No |

Purposes for all: **App Functionality**. No analytics, advertising or
third-party SDKs in the app. If the Privacy Policy, once approved by counsel
(O5), says more or less than this, the label and `PrivacyInfo.xcprivacy`
change with it. Visitor analytics on card.site addresses are data about
*visitors to the user's links*, not about the app user, and are covered by
the Privacy Policy rather than this label — confirm with counsel.

## Age rating

Answer **None** to every content question (violence, sexual content,
profanity, drugs, gambling, horror, medical). Then:

- Unrestricted web access: **No** (links open in the user's browser, not an in-app browser).
- User-generated content: **Yes** — users create addresses and pages that others can open. Cardsite's Acceptable Use Policy and abuse reporting apply (marketing `legal/acceptable-use`, Draft).
- Messaging / chat between users: **No**. Social features (profiles, following): **No**.
- Age assurance / parental controls: **No**.

Expected result: **13+** under the 2026 questionnaire because of
user-generated content. Confirm in App Store Connect; the questionnaire
computes it.

## Screenshots

Required sets (no transparency, 1–10 each):

| Device | Size (portrait) | Shots |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | 1 Links list · 2 Link detail with traffic chart · 3 New Short Link sheet · 4 QR code detail · 5 Sign-in |
| iPad 13" | 2064 × 2752 | 1 Links split view with detail · 2 QR codes · 3 Account |
| Mac | 2880 × 1800 | 1 Links with sidebar · 2 Link detail · 3 New QR Code sheet |

Produce them from the Simulator and the Mac build signed in to a seeded demo
account (realistic link names, a week of traffic), light appearance first.
iPhone Duo screenshots become required only for builds made with the iOS
27.1 SDK or later; plan them for the first update.
