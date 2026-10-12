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
`.response`. Every JWT is replaced with `"<redacted-jwt>"`. Ids, emails and
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
These keys are omitted when unset: `project_id, domain_id, splash_page_id, pixels_ids` (comma-separated **String** in responses), `display_rules, timezone, scheduled_at, scheduled_end`.
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

## Discrepancies vs openapi.yaml

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
