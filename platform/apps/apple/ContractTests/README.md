# Native contract tests

`native-contract.sh` runs the HTTP calls the native Swift client depends on
against a **real, running** Cardsite API. It asserts the status codes and the
presence and JSON type of each field with `jq`. It also writes every response
it sees to `fixtures/` with JWTs redacted, and the Swift model tests decode
those fixtures.

**This file is the source of truth for the Swift models.** Where it disagrees
with `shared/contracts/openapi.yaml`, this file records what the server
actually sent. Each disagreement is listed under [Discrepancies](#discrepancies-vs-openapiyaml).

## Run

```bash
# bash, curl, jq. BASE_URL is an arg or env; default http://localhost:8080
./native-contract.sh http://localhost:8080
WRITE_FIXTURES=0 ./native-contract.sh http://localhost:8080   # assert only
LIMITER_PROBE=1  ./native-contract.sh http://localhost:8080   # also prove the 429 + Retry-After
```

```bash
# Also exercise every endpoint the parity plan needs (fixtures 20–26). Needs
# psql and the API's database URL: the run's user is moved to Enterprise with
# one UPDATE and one inbox notification is seeded with one INSERT.
PSQL_URL='postgres://cardsite@127.0.0.1:55432/cardsite_db?sslmode=disable' ./native-contract.sh http://localhost:58080
# … plus the 2FA sign-in challenge and recovery-code sign-in (3 more counted
# auth calls: start the API with AUTH_RATE_LIMIT_ATTEMPTS>=9). Needs python3.
PSQL_URL=… TWOFA_LOGIN=1 ./native-contract.sh http://localhost:58080
```

The exit code is 0 only when every assertion passes. Lines marked `note` record
known server quirks and never fail the run, so the script keeps passing once
those quirks are fixed.

Each run registers a fresh `native-contract-<id>@example.test` user with a
`nc-<id>` slug. The run deletes that user in step 13.

### Auth limiter budget

register, login, lost-password, reset-password, resend-activation,
activate-user and login/2fa share one fixed-window limiter. It allows
**6 calls per 10 min per client IP, and successful calls count**
(`AUTH_RATE_LIMIT_ATTEMPTS` / `AUTH_RATE_LIMIT_WINDOW_MINUTES`). When the
limit is reached the server answers `429 {"error":{"title":"Too many attempts.
Please try again later.","code":429}}` with `Retry-After: 600`.

The script makes exactly **5** counted calls: register, login, wrong-password
login, lost-password, and login-after-delete. One run therefore fits the
default budget. Step 2 is a CSRF-rejected call. The global CSRF guard refuses
it before the limiter runs, so it does not count.

A second run within 10 minutes fails at step 1 with 429. Either restart the
API (the limiter is in memory), or start a **dev/test** API with
`AUTH_RATE_LIMIT_ATTEMPTS=50`. Both ways were verified: two back-to-back runs
passed with the raised limit. `LIMITER_PROBE=1` deliberately exhausts the
budget.

The PARITY section adds no counted auth calls unless `TWOFA_LOGIN=1`, so
a run with `PSQL_URL` still fits the default budget (verified, run B below).

### How it was proven (2026-10-12, parity extension)

Built from a scratch copy of `/home/claude/src/cardsite-platform_0.0.0/apps/api`
(never in place) with **Go 1.25.1** (`/usr/local/go1.25.1/bin`; the default
`go` on PATH is 1.24.7 and pgx 5.10 needs 1.25, so lowering the `go`
directive does not work). `proxy.golang.org` is unreachable, so the build ran
with `GOPROXY=direct GOSUMDB=off GOTOOLCHAIN=local GOFLAGS=-mod=mod` and this
block appended to the *scratch copy's* go.mod:

```
replace (
	golang.org/x/crypto => github.com/golang/crypto v0.55.0
	golang.org/x/text => github.com/golang/text v0.41.0
	golang.org/x/sync => github.com/golang/sync v0.22.0
	golang.org/x/sys => github.com/golang/sys v0.47.0
	go.uber.org/atomic => github.com/uber-go/atomic v1.11.0
)
```

Postgres 16 (`/usr/lib/postgresql/16/bin`, `initdb -A trust` as the
`postgres` user under its home directory, `:55432`; a data dir under `/tmp`
became unreadable to `postgres` mid-run), Redis on `:56379`, `cmd/migrate
-dir migrations up` (49 migrations), server on `:58080` with the same
environment as below plus `UPLOAD_PATH=<scratch>/uploads`.

| Run | Limiter | Flags | Result |
|---|---|---|---|
| A (wrote `fixtures/`) | `AUTH_RATE_LIMIT_ATTEMPTS=200` | `PSQL_URL`, `TWOFA_LOGIN=1` | **316 passed, 0 failed** |
| B | default (6 / 10 min), fresh API | `PSQL_URL`, `LIMITER_PROBE=1` | **315 passed, 0 failed**; `14-auth-login-429` taken from this run |
| C | default, fresh API | none (PARITY skipped) | **104 passed, 0 failed** |

Every fixture in `fixtures/` is **live** (none is synthetic).

### How it was proven (2026-10-11)

Run against `apps/api` built from source (snapshot of this tree), Go 1.25.1, on
`:58080`. The stack was PostgreSQL 16 in a scratch data dir on `:55432`
(initdb as the `postgres` user, trust auth) and Redis 7 on `:56379`.
Migrations were applied with the ledger runner:
`cmd/migrate -dir migrations up` (49 migrations).

Environment: `ENV=development`, `DATABASE_URL=postgres://cardsite@127.0.0.1:55432/cardsite_db?sslmode=disable`,
`REDIS_URL=redis://127.0.0.1:56379/0`, a random 64-hex `JWT_SECRET`,
`APP_URL=http://localhost:3000`, and default limiters. No SMTP, CAPTCHA, OAuth
or payment keys were set. No seed was needed because the script registers its
own user.

Result: **106 passed, 0 failed**, with `LIMITER_PROBE=1` at the default limit.

(The egress proxy blocks proxy.golang.org. The build resolved `golang.org/x/*`
and `go.uber.org/atomic` from their GitHub mirrors through a `replace` block
in the *snapshot's* go.mod only. Each mirrored module's h1 dirhash was
checked against the repository's `go.sum` and matched.)

### Fixtures

`fixtures/NN-<endpoint>-<status>.json` has the shape
`{"_request":{"method","path","status"}, "response": <exact body>}`. Decode
`.response`. Every JWT is replaced with `"<redacted-jwt>"`, API token secrets with
`"<redacted-token>"`, bcrypt digests with `"<redacted-hash>"`, the TOTP
secret and `otpauth://` URL with `"<redacted-totp>"`, and recovery codes
with `"<redacted-recovery-code>"`. Ids, emails and
timestamps are real values from the run.

| Fixture | Call |
|---|---|
| 01-auth-register-201 | POST /api/v1/auth/register |
| 02-auth-register-403-csrf | same, no `X-Requested-With` |
| 03a-auth-login-200 / 03b-auth-login-401 | POST /api/v1/auth/login (good / wrong password) |
| 04a-user-200 / 04b-user-401 | GET /api/v1/user (bearer / none) |
| 05-workspaces-200 | GET /api/v1/workspaces |
| 06a-links-create-201 | POST /api/v1/links |
| 06b-links-list-200 | GET /api/v1/links?page=1&results_per_page=25 |
| 06c-links-get-200 | GET /api/v1/links/{id} |
| 06d-links-update-disable-200 / 06e-links-update-destination-200 | PUT /api/v1/links/{id} |
| 06f-links-create-409-duplicate | POST /api/v1/links, taken slug |
| 06g-links-create-422-plan-limit | POST /api/v1/links, 2nd slug on Free |
| 07a-statistics-overview-empty-200 / 07b-statistics-overview-200 | GET /api/v1/statistics/{id}?type=overview (before / after one click) |
| 07c-statistics-referrer-200 | GET /api/v1/statistics/{id}?type=referrer (empty → `null`) |
| 07d-statistics-summary-200 | GET /api/v1/statistics |
| 08a-qr-codes-create-201 / 08b-qr-codes-list-200 | POST / GET /api/v1/qr-codes |
| 09-biolinks-list-empty-200 | GET /api/v1/biolinks (empty) |
| 10a-account-plan-200 / 10b-plans-200 | GET /api/v1/account/plan, GET /api/v1/plans |
| 11-account-update-200 | PUT /api/v1/account |
| 12-auth-lost-password-200 | POST /api/v1/auth/lost-password |
| 13a/13b/13c-account-delete-{401,400,200} | DELETE /api/v1/account (wrong / missing / right password) |
| 13d-user-after-delete-401 | GET /api/v1/user with the deleted user's token |
| 14-auth-login-429 | auth limiter tripped |
| **PARITY** (needs `PSQL_URL`) | |
| 20a-statistics-summary-200 | GET /api/v1/statistics (after content; cached, see quirk 5) |
| 20b-statistics-all-overview-200 | GET /api/v1/statistics/all?type=overview&start_date&end_date |
| 20c-statistics-all-country-200 | GET /api/v1/statistics/all?type=country_code (no rows → `null`) |
| 20d-resources-recent-200 | GET /api/v1/resources/recent?limit=5 |
| 20e-spotlight-200 / 20f-spotlight-short-200 | GET /api/v1/spotlight?q=… (≥2 chars / 1 char) |
| 21a / 21b / 21c projects | POST, PUT /{id}, GET /api/v1/projects |
| 21d / 21e domains | POST, GET /api/v1/domains |
| 21f / 21g / 21h pixels | GET /pixels/types, POST, GET /api/v1/pixels |
| 21i / 21j splash pages | POST, GET /api/v1/splash-pages |
| 21k-reference-targeting-200 | GET /api/v1/reference/targeting (public) |
| 22a-links-create-full-201 | POST /api/v1/links with project, domain, splash page, pixel, timezone, schedule, display_rules, password, UTM, clicks limit, cloaking, status code |
| 22b-links-get-full-200 | GET /api/v1/links/{id} (full object) |
| 22c-links-update-full-200 | PUT /api/v1/links/{id} new settings + targeting, `project_id:null` |
| 22d-links-duplicate-201 | POST /api/v1/links/{id}/duplicate |
| 22e-links-list-paged-200 | GET /api/v1/links?page=1&results_per_page=2 |
| 22f-links-delete-200 / 22g-links-get-404 | DELETE /api/v1/links/{id}, then GET → 404 |
| 23a-qr-codes-types-200 | GET /api/v1/qr-codes/types |
| 23b / 23c qr generate | POST /api/v1/qr-codes/generate (200 / 400 nothing to encode) |
| 23d-qr-codes-create-styled-201 / 23e-qr-codes-update-200 | POST (link_id, project_id, colours), PUT /api/v1/qr-codes/{id} |
| 24a-biolinks-create-201 | POST /api/v1/biolinks |
| 24b-biolink-blocks-types-200 | GET /api/v1/biolink-blocks/types (85 types) |
| 24c-biolink-blocks-create-201 | POST /api/v1/biolink-blocks |
| 24d / 24e block update | PUT /api/v1/biolink-blocks/{id} with `version` (200 / 409 stale) |
| 24f-biolink-blocks-order-200 | POST /api/v1/biolink-blocks/order |
| 24g-biolink-blocks-list-200 | GET /api/v1/biolink-blocks?link_id= |
| 24h-biolinks-get-200 | GET /api/v1/biolinks/{id} → `{biolink, blocks}` |
| 24i / 24j | PUT /api/v1/biolinks/{id}, GET /api/v1/biolinks |
| 25a / 25b / 25d vcards | POST, PUT /{id}, GET /api/v1/vcards |
| 25e / 25f / 25h events | POST, PUT /{id}, GET /api/v1/events |
| 25i / 25j / 25k / 25l payment links | POST (201 / 422), PUT /{id}, GET /api/v1/payment-links |
| 25m / 25n / 25o files | POST, PUT /{id} (multipart), GET /api/v1/files |
| 25p / 25q static | POST (multipart), GET /api/v1/static |
| 26a / 26b preferences | GET, PUT /api/v1/account/preferences |
| 26c / 26d / 26e / 26f tokens | POST (201 / 400), GET, DELETE /{id} /api/v1/account/tokens |
| 26g / 26h / 26i password | PUT /api/v1/account/password (401 / 400 / 200) |
| 26j 2fa setup, 26k / 26n status | POST /auth/2fa/setup, GET /auth/2fa/recovery-codes (off / on) |
| 26l / 26m 2fa verify | POST /auth/2fa/verify (401 bad code / 200 + recovery codes) |
| 26o / 26p 2fa sign-in | POST /auth/login → `{twofa_required:true}`; with `recovery_code` → token (`TWOFA_LOGIN=1`) |
| 26q / 26r 2fa disable | DELETE /api/v1/auth/2fa (401 / 200) |
| 26s–26x inbox | GET /internal-notifications (empty / one), /unread, POST /{id}/read, /read-all, /unread again |
| 26y-logs-200 | GET /api/v1/logs?page=1&per_page=25 |
| 26z1 / 26z2 / 26z3 uploads | POST (multipart), GET, DELETE /api/v1/uploads |
| 26z4 / 26z5 / 26z6 data | GET /api/v1/data, GET /{id}, DELETE /{id} (a bio page form submission) |
| 26z7-workspaces-members-200 | GET /api/v1/workspaces/{id}/members |
| 26z8-workspaces-activity-200 | GET /api/v1/workspaces/activity?limit=20 |
| 26z9-workspaces-create-201 | POST /api/v1/workspaces |
| 26z10 / 26z11 | GET /api/v1/links with `X-Workspace-ID` of the new workspace (`null`) / a foreign one (403) |

Asserted but not saved (bodies are not JSON): `GET /vcards/{id}/download`
(vCard), `GET /api/public/events/{slug}/ics` (iCalendar).

## Observed contract (source of truth for Swift)

### Transport rules

- **Every POST/PUT/PATCH/DELETE must send `X-Requested-With: XMLHttpRequest`.**
  Without it the server answers `403 {"error":{"code":403,"title":"CSRF check failed"}}`,
  and this includes register and login. Any non-empty value passes.
- Auth is `Authorization: Bearer <jwt>` only. The server uses no cookies. A
  missing or invalid token gets `401 {"error":{"title":"Unauthorized"|"Invalid or expired token","code":401}}`.
  A token for a deleted user also gets 401 (`Invalid or expired token`).
- Success envelope: `{"data": <payload>}`. Lists add
  `"meta":{"page":Int,"per_page":Int,"total":Int}`, and these are **exactly
  those three keys**. The pagination *request* parameter is
  `results_per_page`; the *response* key is `per_page`.
- **An empty list is `"data": null`, not `[]`** (seen on biolinks and
  statistics). Decode lists as `[T]?` and treat nil as empty.
- Error envelope: `{"error":{"title":String,"code":Int, ...extras}}`. `error`
  is an object and `data` is absent. Extras appear only on some errors: 422
  `plan_limit_exceeded` adds `limit:String, current:Int, max:Int` inside `error`.
- Every response carries `X-Request-Id`.

### Scalar formats

- **ids**: JSON integers (Int64 in Swift) everywhere: `user_id`,
  `workspace_id`, `owner_user_id`, link `id`, qr `id`, `plan_id`, plan `id`.
  They are never strings. Path parameters are the same integers.
- **Timestamps**: RFC 3339 in UTC with a `Z` suffix and **variable fractional
  seconds**, e.g. `2026-10-11T20:02:24.95656Z` (5 digits) and
  `2026-10-11T20:02:25.188241Z` (6 digits). Go trims trailing zeros, so a
  value can have 0–9 digits. `ISO8601DateFormatter` with
  `.withFractionalSeconds` **rejects a value without a fraction**, and the
  plain formatter rejects a value *with* one. Use a decoder strategy that
  tries both. The test regex also allows `±hh:mm`.
- **Dates (statistics)**: `"YYYY-MM-DD"` strings, e.g. `"2026-10-11"`. The
  query params `start_date` and `end_date` use the same format.
- **Prices**: JSON numbers (`*float64` server side) that are **omitted** when
  unset rather than sent as null.

### Endpoints

| # | Call | Status | `data` shape (observed) |
|---|---|---|---|
| 1 | POST /api/v1/auth/register `{name,email,password}` | **201** | `{token:String(JWT), user:User}` |
| 2 | same, no X-Requested-With | **403** | error `{title:"CSRF check failed",code:403}` |
| 3 | POST /api/v1/auth/login `{email,password}` | **200** | `{token, user:User}` (with 2FA on and no code sent: `{twofa_required:true}`, not exercised) |
| 3b | login, wrong password | **401** | error `{title:"Invalid email or password",code:401}` |
| 4 | GET /api/v1/user | **200** / 401 without bearer | `User` |
| 5 | GET /api/v1/workspaces | **200** | `[Workspace]`, no meta |
| 6 | POST /api/v1/links `{url:slug,location_url,type:"link"}` | **201** | `Link` |
| 6b | GET /api/v1/links?page=1&results_per_page=25 | **200** | `[Link]` + meta |
| 6c | GET /api/v1/links/{id} | **200** | `Link` |
| 6d | PUT /api/v1/links/{id} `{is_enabled:false}` | **200** | `Link`. Partial body accepted; omitted fields untouched |
| 6e | PUT /api/v1/links/{id} `{is_enabled:true, location_url}` | **200** | `Link` |
| 6f | POST /api/v1/links with a taken slug | **409** | error `{title:"That address is already taken",code:409}`. The slug check runs **before** the plan-limit check |
| 6g | 2nd link on Free | **422** | error `{title:"plan_limit_exceeded",code:422,limit:"custom_slugs_limit",current:1,max:1}` |
| 7 | GET /api/v1/statistics/{id}?type=overview&start_date&end_date | **200** | `null` when there are no clicks, else `[{date:"YYYY-MM-DD", pageviews:Int, visitors:Int}]` |
| 7c | GET /api/v1/statistics/{id}?type=referrer | **200** | `null` or `[{label:String, pageviews:Int}]` |
| 7d | GET /api/v1/statistics | **200** | `{links,biolinks,qr_codes,projects,domains,pixels,total_clicks}`, all Int |
| 8 | POST /api/v1/qr-codes `{name,type:"url",settings:{url}}` | **201** | `QrCode` |
| 8b | GET /api/v1/qr-codes | **200** | `[QrCode]` + meta. The image is inlined in every row |
| 9 | GET /api/v1/biolinks | **200** | `null` + meta `{page:1,per_page:25,total:0}` for a new user |
| 10 | GET /api/v1/account/plan | **200** | `{plan_id:Int, plan_expiration_date:Date?, plan_settings:Object?, payment_processor:String, payment_subscription_id:String}`. The two strings are `""` when there is no subscription |
| 10b | GET /api/v1/plans | **200** | `[Plan]`, no meta |
| 11 | PUT /api/v1/account `{name}` | **200** | the updated `User` |
| 12 | POST /api/v1/auth/lost-password `{email}` | **200** | `{message:"If an account exists with that email, a reset link has been sent"}` |
| 13 | DELETE /api/v1/account `{password}` wrong | **401** | error `{title:"Password is incorrect",code:401}` |
| 13b | DELETE /api/v1/account `{}` | **400** | error `{title:"Password is required to confirm account deletion",code:400}` |
| 13c | DELETE /api/v1/account right password | **200** | `{message:"Account deleted successfully"}`. The old JWT then gets 401 and login gets 401 |
| 14 | 7th counted auth call in the window | **429** | error `{title:"Too many attempts. Please try again later.",code:429}`, header `Retry-After: 600` |

### Models

`?` marks a field that was null or may be absent.

**User** (register, login, `/user`, `PUT /account`):
`user_id:Int, email:String, name:String, twofa_enabled:Bool, type:Int (0 user, 1 admin), status:Int (1 active), plan_id:Int, plan_expiration_date:Date?, plan_settings:Object?, language:String ("english"), timezone:String ("UTC"), is_newsletter_subscribed:Bool, last_activity:Date, total_logins:Int, created_at:Date, updated_at:Date?`.
These keys are omitted when empty: `payment_processor, payment_subscription_id, billing, preferences, country, source, anti_phishing_code`.
`plan_settings` is **null for a Free user**. Read limits from the matching `Plan.settings` in `/plans`.
`updated_at` is always null.
`total_logins` in the login response is the count *before* this login (0 on the first login).

**Workspace**: `workspace_id:Int, owner_user_id:Int, name:String ("Personal"), is_personal:Bool, created_at:Date, role:String ("owner"), storage_bytes:Int`.

**Link**: `id:Int, user_id:Int, workspace_id:Int, type:String ("link"), url:String (the slug), location_url:String (the destination), settings:Object? (null when unset), clicks:Int, is_verified:Bool, is_enabled:Bool, directory_is_enabled:Bool, created_at:Date, updated_at:Date?, last_used_at:Date, lifecycle_state:String ("active"), lifecycle_state_at:Date`.
These keys are omitted when unset: `project_id, domain_id, splash_page_id, pixels_ids` (a **String** holding a JSON array, e.g. `"[2]"`; see quirk 4), `display_rules, timezone, scheduled_at, scheduled_end`.
The server never generates a slug; the client must send `url`.
A click on `GET /l/{slug}` gives a 302 to `location_url` and raises `clicks` by 1.

**QrCode**: `id:Int, user_id:Int, workspace_id:Int, name:String, type:String, qr_code:String, settings:Object, embedded_data:String, created_at:Date, updated_at:Date?`.
`qr_code` is a `data:image/png;base64,…` URL. The decoded bytes start with the PNG magic `89 50 4E 47 0D 0A 1A 0A`, and the image observed was 256×256.
The server adds `settings._style` (eyes/frame/gradient/size keys with `""`/`0` defaults) next to the `url` the client sent.

**Plan**: `id:Int, name:String, description:String, monthly_price:Double?, annual_price:Double?, trial_days:Int, settings:Object, status:Int, order:Int, created_at:Date`.
Free has `monthly_price:0, annual_price:0`.
Starter, Pro, Business and Business+ have **no `annual_price` key**.
Enterprise has **neither price key**.
`settings` keys observed: `ai_tools, api_is_enabled, custom_pwa_is_enabled, password_protection, premium_blocks, targeting_is_enabled` (Bool) and `custom_slugs_limit, domains_limit, storage_bytes_limit, teams_limit` (Int). A missing quota key means unlimited.
The Free plan has `custom_slugs_limit: 1`, which is what step 6g enforces.

### Server quirks the client must tolerate (asserted as `note`)

1. **`PUT /links/{id}` returns timestamps one write behind.** In the
   response, `updated_at` and `last_used_at` are the row's values from
   *before* this write. After the first edit, the PUT response still shows
   `updated_at:null`, and a GET right after returns the new value. The other
   fields (`is_enabled`, `location_url`) are fresh. Re-GET when timestamps
   matter.
2. **`GET /user` is cached for about 10 min and `PUT /account` does not clear
   that cache**, so GET returns the old name. Use the PUT response as the new
   user.
3. **`directory_is_enabled` differs by endpoint for the same row.** Create,
   get and update return `true`; the list returns `false`. Do not rely on it.

## Parity endpoints (observed 2026-10-12)

`Link-shaped` below means the Link object above (`id, user_id,
workspace_id, type, url, settings, clicks, is_verified, is_enabled,
directory_is_enabled, created_at, updated_at, last_used_at,
lifecycle_state, lifecycle_state_at`, plus `location_url` where the type
has a destination). `{message}` means `data:{message:String}`.

**Paging.** Most lists read `page` + `results_per_page`. `/logs`,
`/internal-notifications`, `/pwas`, `/payments` and `/payment-processors`
read `per_page` instead. The response meta is always `{page, per_page,
total}`. `APIClient.sendPage` sends both names with the same value. None of
the user-facing lists takes `search` or sort parameters, except `/logs`
(`search`, `device_type`, `country_code`, `continent_code`), `/uploads`
(`type`, `kind`) and `/data` (`link_id`, `biolink_block_id`, `type`).

| Call | Status | `data` |
|---|---|---|
| GET /statistics/all?type=overview | 200 | `[{date, pageviews, visitors}]` or `null`; `type=<dimension>` → `[{label, pageviews}]` or `null` |
| GET /resources/recent?limit=1…50 (default 5) | 200 | `[Link-shaped]` of every type, newest first, **no meta**; `[]` when empty |
| GET /spotlight?q= | 200 | `[{type, id, label, url}]`, `type` one of `link`, `biolink`, `user`; `[]` when `q` is under 2 chars |
| POST /projects `{name,color}` · PUT /projects/{id} (partial) | 201 · 200 | `{id,user_id,workspace_id,name,color,created_at,updated_at}` |
| POST /domains `{host,scheme,…}` | 201 | `{id,user_id,workspace_id,scheme,host,type:Int,is_enabled,ssl_is_enabled,force_ssl,redirect_type:String("301"),forward_parameters,is_verified,created_at,updated_at}` |
| GET /pixels/types | 200 | `[{key,name,description,field_label,emits_beacon}]` |
| POST /pixels `{name,type,pixel}` | 201 | `{id,user_id,workspace_id,type,name,pixel,created_at,updated_at}` |
| POST /splash-pages `{name,title,description,link_unlock_seconds,auto_redirect,settings}` | 201 | `{id,user_id,workspace_id,name,title,description,link_unlock_seconds,auto_redirect,created_at}` (`settings` omitted when empty) |
| GET /reference/targeting (no auth) | 200 | `{browsers,continents,countries,device_types,languages,operating_systems}`, each `[{value,label}]` |
| POST /links (full) | 201 | Link + `project_id, domain_id, splash_page_id, pixels_ids, display_rules, timezone, scheduled_at, scheduled_end` |
| POST /links/{id}/duplicate (no body) | 201 | Link; slug `<slug>-copy` (then `-copy-2`…), `is_enabled:false`, `clicks:0`, settings and targeting copied |
| DELETE /links/{id} | 200 | `{message}`; a GET afterwards is 404 `"Link not found"` |
| GET /qr-codes/types | 200 | `[{value,label,group}]` (28) |
| POST /qr-codes/generate | 200 | `{png:"data:image/png;base64,…", embedded_data}`; nothing to encode → 400 |
| POST /qr-codes (styled) | 201 | QrCode + `link_id, project_id, qr_code_foreground, qr_code_background`; `settings._style` holds the stored-but-unrendered style keys |
| POST /biolinks `{url,settings:{title,description}}` | 201 | Link-shaped, `type:"biolink"` |
| GET /biolinks/{id} | 200 | `{biolink: Link-shaped, blocks: [Block]}` |
| PUT /biolinks/{id} | 200 | Link-shaped; takes `settings, display_rules, timezone, scheduled_*, project_id, domain_id, splash_page_id, pixels_ids, is_enabled, directory_is_enabled` |
| GET /biolink-blocks/types | 200 | `[{type,name,category,icon,color,has_statistics,fields:[{name,kind,label,options?:[{value,label}]}]}]` |
| POST /biolink-blocks `{link_id,type,location_url?,settings}` | 201 | Block `{id,user_id,workspace_id,link_id,type,location_url?,settings,clicks,is_enabled,order,version,last_editor_user_id,created_at,updated_at}` |
| PUT /biolink-blocks/{id} `{…, version}` | 200 / **409** | Block with `version+1`; a stale `version` → 409 with extras `at`, `last_editor:{name,user_id}` |
| POST /biolink-blocks/order `{biolink_block_ids:[…]}` | 200 | `{message}` |
| GET /biolink-blocks?link_id= | 200 | `[Block]` + meta |
| POST /vcards (flat `vcard_*`) | 201 | Link-shaped, `type:"vcard"`; every `vcard_*` lands in `settings` (unset ones `""`; `vcard_phone_numbers`/`vcard_socials` are arrays of objects) |
| PUT /vcards/{id} `{url?,settings?,is_enabled?}` | 200 | Link-shaped. **Flat `vcard_*` fields are ignored and `settings` replaces the whole object**: send every field |
| POST /events (flat `event_*`) | 201 | Link-shaped, `type:"event"`; `event_*_datetime` are local `"YYYY-MM-DDTHH:mm"` strings plus `event_timezone` |
| PUT /events/{id} `{settings}` | 200 | Link-shaped (settings replaced) |
| POST /payment-links `{url,location_url,settings}` | 201 / 422 | Link-shaped, `type:"payment_link"`; non-http(s) checkout URL → 422 |
| POST /files (multipart `url`, `file`, optional `password`, `force_download_is_enabled`, `sensitive_content`, `clicks_limit`, `expiration_url`, `project_id`, `domain_id`) | 201 | Link-shaped, `type:"file"`, `settings:{file,file_path,force_download_is_enabled,sensitive_content}` |
| PUT /files/{id} (multipart; `file` optional) | 200 | Link-shaped |
| POST /static (multipart `url`, `file`: HTML, Markdown, SVG or ZIP) | 201 | Link-shaped, `type:"static"`, `settings:{file_path,static_folder,static_kind,sensitive_content,…}` |
| GET / PUT /account/preferences | 200 | free-form object, `{}` when never set; PUT echoes what it stored |
| POST /account/tokens `{name,scopes}` | 201 / 400 | `{secret:"cst_…", notice, token:{id,user_id,workspace_id,name,scopes,last_used_at,expires_at,revoked_at,created_at}}` |
| GET /account/tokens | 200 | `{scopes:[String], tokens:[Token]}` (an object, not a list) |
| DELETE /account/tokens/{id} | 200 | `{message}` |
| PUT /account/password `{current_password,new_password}` | 200 / 401 / 400 | `{message}`; wrong current → **401** `"Current password is incorrect"`; new outside 8–64 → 400. The JWT stays valid |
| POST /auth/2fa/setup | 200 | `{secret, provisioning_url:"otpauth://totp/…"}` |
| POST /auth/2fa/verify `{code}` | 200 / **401** | `{message, recovery_codes:[String]}` (10 codes); wrong code → 401 `"Invalid 2FA code"` |
| GET /auth/2fa/recovery-codes | 200 | `{remaining:Int, twofa_enabled:Bool}` |
| POST /auth/login with 2FA on | 200 | `{twofa_required:true}` exactly; with `recovery_code` → `{token,user,recovery_codes_remaining}` |
| DELETE /auth/2fa `{password}` | 200 / **401** | `{message}`; wrong password → 401 `"Invalid password"` |
| GET /internal-notifications | 200 | `[{id,user_id,for_who,from_who,icon,title,description,url,is_read,datetime}]` + meta, `null` when empty |
| GET /internal-notifications/unread | 200 | `{notifications:[…] or null, unread_count}` (latest 5) |
| POST /internal-notifications/{id}/read, /read-all | 200 | `{message}` |
| GET /logs | 200 | `[{id,user_id,type,ip,device_type?,os_name?,browser_name?,datetime}]` + meta; types seen `login, login.recovery_code, twofa.enabled, twofa.disabled` |
| POST /uploads (multipart `type`=file\|image\|avatar\|favicon\|logo, `file`) | 201 | `{upload_id,user_id,workspace_id,name,original_name,extension,mime_type,size,storage_path,type,url,created_at}`. **The key is `upload_id`, not `id`** |
| GET /data · GET /data/{id} | 200 | `[{id,biolink_block_id,link_id,user_id,workspace_id,type,data:{…},datetime}]` + meta |
| GET /workspaces/{id}/members | 200 | `[{workspace_id,user_id,role,name,email,created_at}]`, no meta |
| GET /workspaces/activity?limit= (≤100, default 25) | 200 | `[{action,actor_user_id,actor_name,at,subject_type?,subject_id?,link_id?}]`; actions `comment.posted, block.created, block.edited, resource.created, member.joined` (`member.joined` has no subject) |
| POST /workspaces `{name}` | 201 | Workspace |
| any call with `X-Workspace-ID` of a workspace you are not in | **403** | `"You are not a member of this workspace"` |

### More quirks (asserted as `note` or documented by an assertion)

4. **`pixels_ids` is a JSON array encoded in a string** in responses
   (`"[2]"`), not the comma-separated string the older notes said. Send an
   array of integers.
5. **`GET /statistics` is cached for 5 minutes per user** and creates do not
   clear it, so the counts lag right after a create.
6. **`/resources/recent` rows have `lifecycle_state:""`** and
   `last_used_at`/`lifecycle_state_at` `"0001-01-01T00:00:00Z"`: the query
   does not select those columns. `Resource.isLapsing` treats `""` as
   unknown, not lapsing.
7. **`/spotlight` is not scoped to the caller.** It searches every
   account's enabled links and directory-listed bio pages. Do not use it as
   "search my resources".
8. **`settings` is replaced, not merged, on PUT.** Observed on links and
   vCards; the event, payment link and bio page handlers also take
   `settings` as one whole object. `password_hash` is the one key carried
   forward when `password` is absent (observed); the web client sends
   `password:""` to clear it (not exercised here).
9. **The bcrypt `settings.password_hash` is sent to the client** on every
   link with a password. Use its presence as "has a password"; never show it.
10. **`token.workspace_id` is the real id on create and `0` in the list.**
11. **The sign-in response's `user.twofa_enabled` is `false`** even when
    the sign-in needed a recovery code. Read `GET /auth/2fa/recovery-codes`.
12. **A wrong password or code on `PUT /account/password`,
    `POST /auth/2fa/verify` and `DELETE /auth/2fa` is a 401**, the same
    status as an expired session. The client must send these with
    `credentialCheck: true` or it signs the user out.
13. `GET /internal-notifications/unread` sends `notifications:null` when
    nothing is unread.

## Discrepancies vs openapi.yaml

The list below was checked on 2026-10-11 for the original endpoint set. The
2026-10-12 parity endpoints were **not** audited field by field against the
spec; the spec has paths for all of them and already documents
`per_page` versus `results_per_page` and `upload_id`. Quirks 4–13 above are
the behaviour to code against.

Checked against `shared/contracts/openapi.yaml` (info.version 1.0.0) as it
stood on 2026-10-11. Most of the older drift (error envelope as a string,
`per_page`, link `url` semantics, register 201) has **already been corrected**
in the spec. What remains:

1. **Empty lists are `data: null`.** `APIResponse.data` is described as
   "object or array", and the spec never says that an empty list serialises
   as null (biolinks, statistics).
2. **`GET /api/v1/statistics/{link_id}` documents no query parameters**
   (`type`, `start_date`, `end_date`, `limit`) and no response shape. The
   path param is typed `string`, but the server takes an integer link id (or
   `all`). Observed: overview rows `{date:"YYYY-MM-DD", pageviews, visitors}`,
   grouped rows `{label, pageviews}`, and `null` when empty.
3. **`User.plan_settings`** is required and typed `object`, and is described
   as "the effective plan's quotas… resolved for this account". **Observed
   `null`** for a Free user. The same holds in `/account/plan`, which has no
   schema in the spec at all.
4. **`Plan.monthly_price` / `annual_price`** are typed `nullable: true`, but
   the server **omits** them (`omitempty`) rather than sending null.
5. **`Link.settings`** is required and typed `object` without `nullable`.
   **Observed `null`.** `Link.location_url` is not in `required`, yet it is
   present on every `type:"link"` row.
6. **`PUT /api/v1/links/{link_id}` request body is `{type: object}`** with no
   properties listed. Observed accepted: partial `{is_enabled}` and
   `{location_url}`. Neither the stale-timestamp response (quirk 1) nor the
   `directory_is_enabled` inconsistency (quirk 3) is documented.
7. **`QrCode.settings`** gets a server-added `_style` object, which is
   undocumented. The image size (256 px) is undocumented.
8. **The spec does not give response schemas** for `/workspaces`, `/links`,
   `/qr-codes`, `/biolinks`, `/account/plan`, `/plans`, `/statistics`, or
   `PUT /account`. They are all bare `APIResponse`. The component schemas
   `Workspace`, `Link`, `QrCode` and `Plan` exist but no operation
   references them.
9. **The YAML has unquoted commas inside flow mappings**, so the
   descriptions parse into stray keys. Under a YAML parser:
   - register and login `403` become `{"description":"Registration is closed","or the CSRF header is missing":null}`
   - the same happens to `QrCode.link_id` (`"where it represents one"`)
   - `POST /qr-codes` `link_id` (`"if any"`)
   - `Workspace.role` (`"populated on listing"`)
   - `ErrorObject.code` (`"repeated"`)

   Code generators will mis-handle these.
10. **`DELETE /api/v1/account`** documents `409 active_subscription`. The
    snapshot this run was built from does not have that branch (another
    change in flight adds it). The 401/400/200 paths matched the spec.
11. **The login 200 description** says `{token, user, recovery_codes_remaining?}`.
    Observed `{token, user}`; `recovery_codes_remaining` is absent without
    2FA. This is consistent with the spec, noted here for the decoder.
12. **The `/user` caching** (quirk 2) is undocumented.
13. Matches the spec, listed for completeness:
    - 429 `Retry-After: 600` on auth routes
    - the CSRF 403 body
    - the 422 `plan_limit_exceeded` shape
    - meta keys
    - `results_per_page`
    - `url` = slug
    - `qr_code` data URL
