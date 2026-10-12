#!/usr/bin/env bash
# native-contract.sh — prove the HTTP contract the native Swift client relies on,
# against a REAL running Cardsite API. bash + curl + jq only.
#
# Usage:
#   ./native-contract.sh [BASE_URL]            # default http://localhost:8080
#   BASE_URL=http://localhost:58080 ./native-contract.sh
#
# Env:
#   FIXTURE_DIR      where captured responses go (default: <script dir>/fixtures)
#   WRITE_FIXTURES   1 (default) writes redacted JSON fixtures; 0 = assert only
#   LIMITER_PROBE    1 = after the run, call /auth/login until the auth limiter
#                    answers 429, and assert Retry-After (default 0). Leaves the
#                    calling IP locked out of auth routes for the window.
#   PSQL_URL         a libpq URL for the API's database, e.g.
#                    postgres://cardsite@127.0.0.1:55432/cardsite_db?sslmode=disable
#                    When set (and psql is on PATH), the PARITY section runs:
#                    the run's user is moved to the Enterprise plan with one
#                    UPDATE, a notification is seeded with one INSERT, and
#                    every endpoint the parity plan needs is exercised. Unset,
#                    the section is skipped with a note. Dev/test stacks only.
#   TWOFA_LOGIN      1 = in PARITY, also sign in through the 2FA challenge
#                    (3 more counted auth calls; needs AUTH_RATE_LIMIT_ATTEMPTS
#                    >= 9). Needs python3 for the TOTP code. Default 0.
#
# Auth limiter budget: the server allows AUTH_RATE_LIMIT_ATTEMPTS (default 6)
# calls per AUTH_RATE_LIMIT_WINDOW_MINUTES (default 10) per IP to register,
# login, lost-password, …, and successes count. This script makes exactly FIVE
# such calls (register, login, wrong login, lost-password, login after delete),
# so ONE run fits the default budget. A CSRF-rejected call (step 2) is refused
# by the global CSRF guard before the limiter and does not count. To rerun
# within 10 minutes, restart the API (the limiter is in memory) or start it
# with AUTH_RATE_LIMIT_ATTEMPTS=50 (dev/test stacks only).
#
# Every run creates a fresh user and deletes it at the end (step 13).

set -uo pipefail

BASE_URL="${1:-${BASE_URL:-http://localhost:8080}}"
BASE_URL="${BASE_URL%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="${FIXTURE_DIR:-$SCRIPT_DIR/fixtures}"
WRITE_FIXTURES="${WRITE_FIXTURES:-1}"
LIMITER_PROBE="${LIMITER_PROBE:-0}"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 2; }

RUN_ID="$(date +%s)$RANDOM"
EMAIL="native-contract-$RUN_ID@example.test"
PASSWORD="contract-pass-$RUN_ID"
NAME="Native Contract"
SLUG="nc-$RUN_ID"
SLUG2="nc2-$RUN_ID"

XRW='X-Requested-With: XMLHttpRequest'
CT='Content-Type: application/json'
TOKEN=""
PASS=0
FAIL=0
STATUS=""
BODY=""
HEADERS=""

# Timestamps: RFC 3339, fractional seconds 0–9 digits (Go trims trailing
# zeros, so the digit count VARIES between values), zone Z or ±hh:mm.
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$'
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# req METHOD PATH [JSON_BODY] [extra curl args...]
# Sets STATUS, BODY, HEADERS. Sends X-Requested-With unless NO_XRW=1, and the
# bearer token when TOKEN is set unless NO_AUTH=1.
req() {
  local method="$1" path="$2" body="${3:-}"; shift 3 2>/dev/null || shift $#
  local args=(-sS -X "$method" -D "$tmp/h" -o "$tmp/b" -w '%{http_code}' -H 'Accept: application/json')
  [[ "${NO_XRW:-0}" == 1 ]] || args+=(-H "$XRW")
  [[ -n "$TOKEN" && "${NO_AUTH:-0}" != 1 ]] && args+=(-H "Authorization: Bearer $TOKEN")
  [[ -n "$body" ]] && args+=(-H "$CT" --data "$body")
  STATUS="$(curl "${args[@]}" "$@" "$BASE_URL$path")" || STATUS="000"
  BODY="$(cat "$tmp/b")"
  HEADERS="$(tr -d '\r' < "$tmp/h")"
}

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
note() { printf '  note %s\n' "$1"; }   # observed behaviour, never fails the run
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2" | head -c 800; }
step() { printf '\n%s\n' "$1"; }

expect_status() { # expected... (any of)
  local s
  for s in "$@"; do [[ "$STATUS" == "$s" ]] && { ok "HTTP $STATUS"; return 0; }; done
  bad "HTTP $STATUS (wanted $*)" "$BODY"; return 1
}

# expect 'jq boolean expression' 'description'
expect() {
  if jq -e --arg ts "$TS_RE" --arg date "$DATE_RE" "$1" <<<"$BODY" >/dev/null 2>&1; then ok "$2"
  else bad "$2  [jq: $1]" "$BODY"; fi
}

# Common jq helpers, prepended to expressions.
J_ERR='(.error|type=="object") and (.error.title|type=="string") and (.error.code|type=="number")'
J_TS_OR_NULL='(. == null) or (type=="string" and test($ts))'

# Save the current BODY as fixtures/<name>.json with secrets redacted:
# JWTs become "<redacted-jwt>", API token secrets (cst_…) "<redacted-token>",
# bcrypt digests "<redacted-hash>", TOTP secrets and otpauth URLs
# "<redacted-totp>", and recovery codes "<redacted-recovery-code>".
save() {
  [[ "$WRITE_FIXTURES" == 1 ]] || return 0
  mkdir -p "$FIXTURE_DIR"
  jq --arg s "$STATUS" --arg m "$1" --arg p "$2" '
      walk(if type=="string" and test("^eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$") then "<redacted-jwt>"
           elif type=="string" and test("^cst_") then "<redacted-token>"
           elif type=="string" and test("^\\$2[aby]\\$") then "<redacted-hash>"
           elif type=="string" and test("^otpauth://") then "<redacted-totp>"
           elif type=="object" and (.secret|type)=="string" and has("provisioning_url") then .secret="<redacted-totp>"
           elif type=="object" and (.recovery_codes|type)=="array" then .recovery_codes|=map("<redacted-recovery-code>")
           else . end)
      | {"_request": {"method": $m, "path": $p, "status": ($s|tonumber)}, "response": .}' \
     <<<"$BODY" > "$FIXTURE_DIR/$3.json" 2>/dev/null \
   || bad "could not save fixture $3 (body not JSON)" "$BODY"
}

echo "Native contract run against $BASE_URL"
echo "user=$EMAIL slug=$SLUG"

# ─── 1. Register ────────────────────────────────────────────────────────────
step "1. POST /api/v1/auth/register (with X-Requested-With)"
REG_BODY="$(jq -nc --arg n "$NAME" --arg e "$EMAIL" --arg p "$PASSWORD" '{name:$n,email:$e,password:$p}')"
req POST /api/v1/auth/register "$REG_BODY"
expect_status 201
expect '.data.token|type=="string" and length>20' 'data.token is a JWT string'
expect '.data.user|type=="object"' 'data.user is an object'
expect '.data.user.user_id|type=="number"' 'user.user_id is an integer'
expect '.data.user.email|type=="string"' 'user.email string'
expect '.data.user.name|type=="string"' 'user.name string'
expect '(.data.user.twofa_enabled|type=="boolean") and (.data.user.is_newsletter_subscribed|type=="boolean")' 'user booleans'
expect '(.data.user.type|type=="number") and (.data.user.status|type=="number") and (.data.user.plan_id|type=="number") and (.data.user.total_logins|type=="number")' 'user type/status/plan_id/total_logins are integers'
expect '(.data.user.language|type=="string") and (.data.user.timezone|type=="string")' 'user language/timezone strings'
expect '(.data.user.created_at|type=="string" and test($ts)) and (.data.user.last_activity|type=="string" and test($ts))' 'user created_at/last_activity RFC 3339'
expect "(.data.user.updated_at|$J_TS_OR_NULL) and (.data.user.plan_expiration_date|$J_TS_OR_NULL)" 'user updated_at/plan_expiration_date RFC 3339 or null'
expect '(.data.user.plan_settings == null) or (.data.user.plan_settings|type=="object")' 'user.plan_settings object or null'
TOKEN="$(jq -r '.data.token // empty' <<<"$BODY")"
USER_ID="$(jq -r '.data.user.user_id // empty' <<<"$BODY")"
save POST /api/v1/auth/register 01-auth-register-201
[[ -n "$TOKEN" ]] || { echo "cannot continue without a token"; exit 1; }

# ─── 2. CSRF: same write without X-Requested-With ──────────────────────────
step "2. POST /api/v1/auth/register WITHOUT X-Requested-With → 403 (CSRF guard)"
NO_XRW=1 NO_AUTH=1 req POST /api/v1/auth/register "$(jq -nc --arg e "csrf-$EMAIL" '{name:"x",email:$e,password:"abcdefgh12"}')"
expect_status 403
expect "$J_ERR and .error.code==403 and .error.title==\"CSRF check failed\"" 'error envelope {title:"CSRF check failed",code:403}'
save POST /api/v1/auth/register 02-auth-register-403-csrf

# ─── 3. Login ───────────────────────────────────────────────────────────────
step "3. POST /api/v1/auth/login"
NO_AUTH=1 req POST /api/v1/auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
expect_status 200
expect '.data.token|type=="string" and length>20' 'data.token string'
expect '.data.user.user_id|type=="number"' 'data.user.user_id integer'
expect '(.data.twofa_required // false) == false' 'no 2FA challenge for a fresh account'
TOKEN="$(jq -r '.data.token // empty' <<<"$BODY")"
save POST /api/v1/auth/login 03a-auth-login-200

step "3b. POST /api/v1/auth/login wrong password → 401 object envelope"
NO_AUTH=1 req POST /api/v1/auth/login "$(jq -nc --arg e "$EMAIL" '{email:$e,password:"definitely-wrong-1"}')"
expect_status 401
expect "$J_ERR and .error.code==401" 'error is {title:string, code:401}'
expect '.data == null' 'no data on error'
save POST /api/v1/auth/login 03b-auth-login-401

# ─── 4. Current user ────────────────────────────────────────────────────────
step "4. GET /api/v1/user"
req GET /api/v1/user
expect_status 200
expect '(.data.user_id|tostring)=="'"$USER_ID"'"' 'data.user_id matches registered user'
expect '.data.email|type=="string"' 'data.email string'
save GET /api/v1/user 04a-user-200

step "4b. GET /api/v1/user without Bearer → 401"
NO_AUTH=1 req GET /api/v1/user
expect_status 401
expect "$J_ERR and .error.code==401" 'error envelope code 401'
save GET /api/v1/user 04b-user-401

# ─── 5. Workspaces ──────────────────────────────────────────────────────────
step "5. GET /api/v1/workspaces"
req GET /api/v1/workspaces
expect_status 200
expect '.data|type=="array" and length>=1' 'data is a non-empty array'
expect '.data[0]|(.workspace_id|type=="number") and (.owner_user_id|type=="number") and (.name|type=="string") and (.is_personal|type=="boolean") and (.role|type=="string") and (.storage_bytes|type=="number")' 'workspace fields typed'
expect '.data[0].created_at|test($ts)' 'workspace created_at RFC 3339'
expect '[.data[]|select(.is_personal)]|length==1' 'exactly one personal workspace'
save GET /api/v1/workspaces 05-workspaces-200

# ─── 6. Links ───────────────────────────────────────────────────────────────
LINK_FIELDS='(.id|type=="number") and (.user_id|type=="number") and (.workspace_id|type=="number") and (.type=="link") and (.url|type=="string") and (.location_url|type=="string") and (.clicks|type=="number") and (.is_enabled|type=="boolean") and (.is_verified|type=="boolean") and (.directory_is_enabled|type=="boolean") and (.lifecycle_state|type=="string") and (.created_at|test($ts)) and (.last_used_at|test($ts)) and (.lifecycle_state_at|test($ts)) and ((.updated_at==null) or (.updated_at|test($ts))) and ((.settings==null) or (.settings|type=="object"))'

step "6. POST /api/v1/links {url:<slug>, location_url, type:link}"
req POST /api/v1/links "$(jq -nc --arg s "$SLUG" '{url:$s,location_url:"https://example.com",type:"link"}')"
expect_status 201
expect ".data|$LINK_FIELDS" 'link fields present and typed'
expect '.data.url=="'"$SLUG"'"' 'url echoes the slug (url = slug, not destination)'
expect '.data.location_url=="https://example.com"' 'location_url is the destination'
expect '.data.clicks==0 and .data.is_enabled==true and .data.lifecycle_state=="active"' 'new link: 0 clicks, enabled, active'
LINK_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/links 06a-links-create-201

step "6b. GET /api/v1/links?page=1&results_per_page=25"
req GET '/api/v1/links?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'data is an array of 1'
expect ".data[0]|$LINK_FIELDS" 'list item has link fields'
expect '.meta|keys==["page","per_page","total"]' 'meta keys are exactly page, per_page, total'
expect '.meta.page==1 and .meta.per_page==25 and .meta.total==1' 'meta values'
save GET '/api/v1/links?page=1&results_per_page=25' 06b-links-list-200

step "6c. GET /api/v1/links/{id}"
req GET "/api/v1/links/$LINK_ID"
expect_status 200
expect ".data|$LINK_FIELDS" 'link fields'
save GET "/api/v1/links/{id}" 06c-links-get-200

step "6d. PUT /api/v1/links/{id} {is_enabled:false}"
req PUT "/api/v1/links/$LINK_ID" '{"is_enabled":false}'
expect_status 200
expect '.data.is_enabled==false' 'is_enabled toggled off (partial body accepted)'
expect '.data.location_url=="https://example.com"' 'other fields untouched'
save PUT "/api/v1/links/{id}" 06d-links-update-disable-200

step "6e. PUT /api/v1/links/{id} {is_enabled:true, location_url}"
req PUT "/api/v1/links/$LINK_ID" '{"is_enabled":true,"location_url":"https://example.org/changed"}'
expect_status 200
expect '.data.is_enabled==true and .data.location_url=="https://example.org/changed"' 'destination changed, re-enabled'
expect '.data.updated_at|test($ts)' 'updated_at now set'
save PUT "/api/v1/links/{id}" 06e-links-update-destination-200
PUT_UPDATED="$(jq -r '.data.updated_at' <<<"$BODY")"
req GET "/api/v1/links/$LINK_ID"
GET_UPDATED="$(jq -r '.data.updated_at' <<<"$BODY")"
[[ "$PUT_UPDATED" == "$GET_UPDATED" ]] && note "PUT response updated_at matches a fresh GET" \
  || note "PUT response updated_at ($PUT_UPDATED) lags a fresh GET ($GET_UPDATED): re-GET for timestamps"

step "6f. POST /api/v1/links duplicate slug → 409"
req POST /api/v1/links "$(jq -nc --arg s "$SLUG" '{url:$s,location_url:"https://example.com",type:"link"}')"
expect_status 409
expect "$J_ERR and .error.code==409" '409 error envelope'
save POST /api/v1/links 06f-links-create-409-duplicate

step "6g. POST /api/v1/links second slug on Free (custom_slugs_limit=1) → 422"
req POST /api/v1/links "$(jq -nc --arg s "$SLUG2" '{url:$s,location_url:"https://example.com",type:"link"}')"
expect_status 422
expect "$J_ERR and .error.code==422 and .error.title==\"plan_limit_exceeded\"" 'title plan_limit_exceeded'
expect '(.error.limit|type=="string") and (.error.current|type=="number") and (.error.max|type=="number")' 'limit/current/max inside error'
save POST /api/v1/links 06g-links-create-422-plan-limit

# ─── 7. Statistics ──────────────────────────────────────────────────────────
START="$(date -u -d '-7 days' +%F 2>/dev/null || date -u -v-7d +%F)"
END="$(date -u +%F)"
STATS_PATH="/api/v1/statistics/$LINK_ID?type=overview&start_date=$START&end_date=$END"

step "7. GET /api/v1/statistics/{id}?type=overview (no clicks yet)"
req GET "$STATS_PATH"
expect_status 200
expect '.data==null or .data==[]' 'no clicks → data is null (or [])'
save GET "/api/v1/statistics/{id}?type=overview&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD" 07a-statistics-overview-empty-200

step "7b. GET /l/{slug} (one click), then overview again"
NO_AUTH=1 NO_XRW=1 req GET "/l/$SLUG" ""
expect_status 301 302 307 308
grep -qi '^location: https://example.org/changed' <<<"$HEADERS" && ok 'redirects to location_url' || bad 'redirect Location' "$HEADERS"
req GET "$STATS_PATH"
expect_status 200
expect '.data|type=="array" and length>=1' 'data is an array'
expect '.data[0]|(.date|type=="string" and test($date)) and (.pageviews|type=="number") and (.visitors|type=="number")' 'rows {date:"YYYY-MM-DD", pageviews:int, visitors:int}'
save GET "/api/v1/statistics/{id}?type=overview&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD" 07b-statistics-overview-200
req GET "/api/v1/links/$LINK_ID"
expect '.data.clicks==1' 'link.clicks incremented to 1'

step "7c. GET /api/v1/statistics/{id}?type=referrer"
req GET "/api/v1/statistics/$LINK_ID?type=referrer&start_date=$START&end_date=$END"
expect_status 200
expect '.data==null or (.data|type=="array" and all(.[]; (.label|type=="string") and (.pageviews|type=="number")))' 'data null or [{label, pageviews}]'
save GET "/api/v1/statistics/{id}?type=referrer&..." 07c-statistics-referrer-200

step "7d. GET /api/v1/statistics (account counts)"
req GET /api/v1/statistics
expect_status 200
expect '.data|(.links|type=="number") and (.biolinks|type=="number") and (.qr_codes|type=="number") and (.projects|type=="number") and (.domains|type=="number") and (.pixels|type=="number") and (.total_clicks|type=="number")' 'counts are integers'
save GET /api/v1/statistics 07d-statistics-summary-200

# ─── 8. QR codes ────────────────────────────────────────────────────────────
QR_FIELDS='(.id|type=="number") and (.user_id|type=="number") and (.workspace_id|type=="number") and (.name|type=="string") and (.type=="url") and (.qr_code|type=="string") and (.settings|type=="object") and (.created_at|test($ts)) and ((.updated_at==null) or (.updated_at|test($ts)))'

step "8. POST /api/v1/qr-codes {name, type:url, settings:{url}}"
req POST /api/v1/qr-codes '{"name":"Native contract QR","type":"url","settings":{"url":"https://example.com"}}'
expect_status 201
expect ".data|$QR_FIELDS" 'qr fields present and typed'
expect '.data.qr_code|startswith("data:image/png;base64,")' 'qr_code is a data:image/png;base64 URL'
expect '.data.settings.url=="https://example.com"' 'settings.url echoed'
expect '.data.embedded_data=="https://example.com"' 'embedded_data is the encoded payload'
QR_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
magic="$(jq -r '.data.qr_code|sub("^data:image/png;base64,";"")' <<<"$BODY" | base64 -d 2>/dev/null | head -c 8 | od -An -tx1 | tr -d ' \n')"
[[ "$magic" == "89504e470d0a1a0a" ]] && ok "decoded qr_code starts with PNG magic 89 50 4E 47 0D 0A 1A 0A" || bad "PNG magic" "$magic"
save POST /api/v1/qr-codes 08a-qr-codes-create-201

step "8b. GET /api/v1/qr-codes"
req GET '/api/v1/qr-codes?page=1&results_per_page=25'
expect_status 200
expect ".data|type==\"array\" and length==1 and (.[0]|$QR_FIELDS)" 'array of qr codes (image inlined in list)'
expect '.meta|keys==["page","per_page","total"]' 'meta page/per_page/total'
save GET '/api/v1/qr-codes?page=1&results_per_page=25' 08b-qr-codes-list-200

step "8c. GET /api/v1/qr-codes/{id}"
req GET "/api/v1/qr-codes/$QR_ID"
expect_status 200
expect ".data|$QR_FIELDS" 'qr fields'

# ─── 9. Bio pages ───────────────────────────────────────────────────────────
step "9. GET /api/v1/biolinks (bio pages)"
req GET '/api/v1/biolinks?page=1&results_per_page=25'
expect_status 200
expect '.data==null or (.data|type=="array")' 'empty list is data:null (or [])'
expect '.meta|keys==["page","per_page","total"]' 'meta present even when empty'
expect '.meta.total==0' 'no bio pages yet'
save GET '/api/v1/biolinks?page=1&results_per_page=25' 09-biolinks-list-empty-200

# ─── 10. Plan ───────────────────────────────────────────────────────────────
step "10. GET /api/v1/account/plan"
req GET /api/v1/account/plan
expect_status 200
expect '.data|(.plan_id|type=="number") and (.payment_processor|type=="string") and (.payment_subscription_id|type=="string") and (has("plan_expiration_date")) and (has("plan_settings"))' 'plan_id int, processor/subscription strings ("" when none)'
expect '(.data.plan_settings==null) or (.data.plan_settings|type=="object")' 'plan_settings object or null'
save GET /api/v1/account/plan 10a-account-plan-200

step "10b. GET /api/v1/plans"
req GET /api/v1/plans
expect_status 200
expect '.data|type=="array" and length>=1' 'array of plans'
expect 'all(.data[]; (.id|type=="number") and (.name|type=="string") and (.trial_days|type=="number") and (.settings|type=="object") and (.status|type=="number") and (.order|type=="number") and (.created_at|test($ts)))' 'plan fields typed'
expect 'all(.data[]; ((.monthly_price==null) or (.monthly_price|type=="number")) and ((.annual_price==null) or (.annual_price|type=="number")))' 'monthly_price/annual_price number or ABSENT (omitempty *float64)'
expect '[.data[]|select(.name=="Free")][0].settings.custom_slugs_limit==1' 'Free plan custom_slugs_limit == 1'
save GET /api/v1/plans 10b-plans-200

# ─── PARITY: every endpoint the parity plan (docs/launch/PARITY-PLAN.md) needs ─
# Runs only with PSQL_URL (see the header). Fixtures 20–26. The user is moved
# to the Enterprise plan first, so plan quotas never interfere.
if [[ -n "${PSQL_URL:-}" ]] && command -v psql >/dev/null; then
PARITY_RAN=1
psql_do() { psql "$PSQL_URL" -qAtX -v ON_ERROR_STOP=1 -c "$1"; }

step "P0. Promote the run's user to Enterprise (SQL, test stacks only)"
if psql_do "UPDATE users SET plan_id = (SELECT plan_id FROM plans WHERE name = 'Enterprise' ORDER BY plan_id LIMIT 1) WHERE user_id = $USER_ID" >/dev/null; then
  ok "user $USER_ID is on Enterprise"
else
  bad "could not promote the user"
fi

TS_FUT_A="2030-01-01T09:00:00Z"
TS_FUT_B="2030-02-01T09:00:00Z"

# ── 21. Organise: projects, domains, pixels, splash pages, targeting ─────────
OWNED='(.id|type=="number") and (.user_id|type=="number") and (.workspace_id|type=="number") and (.created_at|test($ts)) and ((.updated_at==null) or (.updated_at|test($ts)))'
META='(.meta|keys==["page","per_page","total"])'

step "P21a. POST /api/v1/projects"
req POST /api/v1/projects '{"name":"Launch","color":"#3366ff"}'
expect_status 201
expect ".data|$OWNED and (.name==\"Launch\") and (.color==\"#3366ff\")" 'project {id,user_id,workspace_id,name,color,created_at,updated_at}'
PROJECT_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/projects 21a-projects-create-201

step "P21b. PUT /api/v1/projects/{id} {name}"
req PUT "/api/v1/projects/$PROJECT_ID" '{"name":"Launch week"}'
expect_status 200
expect '.data.name=="Launch week" and .data.color=="#3366ff"' 'partial update keeps color'
save PUT "/api/v1/projects/{id}" 21b-projects-update-200

step "P21c. GET /api/v1/projects"
req GET '/api/v1/projects?page=1&results_per_page=25'
expect_status 200
expect ".data|type==\"array\" and length==1 and (.[0]|$OWNED)" 'array of projects'
expect "$META" 'meta page/per_page/total'
save GET '/api/v1/projects?page=1&results_per_page=25' 21c-projects-list-200

step "P21d. POST /api/v1/domains"
req POST /api/v1/domains "$(jq -nc --arg h "nc-$RUN_ID.example.test" '{host:$h,scheme:"https://"}')"
expect_status 201
expect ".data|$OWNED and (.host|type==\"string\") and (.scheme==\"https://\") and (.type|type==\"number\") and (.is_enabled|type==\"boolean\") and (.is_verified==false) and (.ssl_is_enabled|type==\"boolean\") and (.force_ssl|type==\"boolean\") and (.redirect_type|type==\"string\") and (.forward_parameters|type==\"boolean\")" 'domain fields typed (redirect_type is a String, e.g. "301")'
DOMAIN_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/domains 21d-domains-create-201

step "P21e. GET /api/v1/domains"
req GET '/api/v1/domains?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'array of domains'
save GET '/api/v1/domains?page=1&results_per_page=25' 21e-domains-list-200

step "P21f. GET /api/v1/pixels/types"
req GET /api/v1/pixels/types
expect_status 200
expect '.data|type=="array" and length>=1 and all(.[]; (.key|type=="string") and (.name|type=="string") and (.description|type=="string") and (.field_label|type=="string") and (.emits_beacon|type=="boolean"))' '[{key,name,description,field_label,emits_beacon}]'
save GET /api/v1/pixels/types 21f-pixels-types-200

step "P21g. POST /api/v1/pixels"
req POST /api/v1/pixels '{"name":"Ads","type":"facebook","pixel":"1234567890"}'
expect_status 201
expect ".data|$OWNED and (.type==\"facebook\") and (.name==\"Ads\") and (.pixel==\"1234567890\")" 'pixel {id,…,type,name,pixel}'
PIXEL_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/pixels 21g-pixels-create-201

step "P21h. GET /api/v1/pixels"
req GET '/api/v1/pixels?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'array of pixels'
save GET '/api/v1/pixels?page=1&results_per_page=25' 21h-pixels-list-200

step "P21i. POST /api/v1/splash-pages"
req POST /api/v1/splash-pages '{"name":"Wait","title":"One moment","description":"Taking you there","link_unlock_seconds":5,"auto_redirect":true,"settings":{}}'
expect_status 201
expect ".data|(.id|type==\"number\") and (.name==\"Wait\") and (.title|type==\"string\") and (.description|type==\"string\") and (.link_unlock_seconds==5) and (.auto_redirect==true) and (.created_at|test(\$ts))" 'splash page fields'
SPLASH_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/splash-pages 21i-splash-pages-create-201

step "P21j. GET /api/v1/splash-pages"
req GET '/api/v1/splash-pages?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'array of splash pages'
save GET '/api/v1/splash-pages?page=1&results_per_page=25' 21j-splash-pages-list-200

step "P21k. GET /api/v1/reference/targeting (public)"
NO_AUTH=1 req GET /api/v1/reference/targeting
expect_status 200
expect '.data|keys==["browsers","continents","countries","device_types","languages","operating_systems"]' 'six option lists'
expect '[.data[][]]|all((.value|type=="string") and (.label|type=="string"))' 'every option is {value,label}'
save GET /api/v1/reference/targeting 21k-reference-targeting-200

# ── 22. Links: the full object ───────────────────────────────────────────────
SLUG_FULL="ncf-$RUN_ID"
FULL_BODY="$(jq -nc --arg s "$SLUG_FULL" --argjson p "$PROJECT_ID" --argjson d "$DOMAIN_ID" --argjson sp "$SPLASH_ID" --argjson px "$PIXEL_ID" --arg a "$TS_FUT_A" --arg b "$TS_FUT_B" '{
  type:"link", url:$s, location_url:"https://example.com/full",
  project_id:$p, domain_id:$d, splash_page_id:$sp, pixels_ids:[$px],
  timezone:"Europe/London", scheduled_at:$a, scheduled_end:$b,
  display_rules:{countries:["GB","US"], device_types:["mobile"], languages:["en"]},
  settings:{password:"open-sesame", clicks_limit:100, expiration_url:"https://example.com/expired",
    sensitive_content:true, http_status_code:301, forward_query_parameters_is_enabled:true,
    utm_source:"newsletter", utm_medium:"email", utm_campaign:"launch",
    cloaking_is_enabled:true, cloaking_title:"Cloaked"}}')"

step "P22a. POST /api/v1/links with targeting, password, UTM, schedule, project, domain, splash, pixel"
req POST /api/v1/links "$FULL_BODY"
expect_status 201
expect ".data|$LINK_FIELDS" 'link fields'
expect ".data.project_id==$PROJECT_ID and .data.domain_id==$DOMAIN_ID and .data.splash_page_id==$SPLASH_ID" 'project_id/domain_id/splash_page_id echoed as integers'
expect '.data.pixels_ids|type=="string"' 'pixels_ids comes back as a STRING'
note "pixels_ids observed: $(jq -c '.data.pixels_ids' <<<"$BODY") (a JSON array encoded in a string; send an array of ints)"
expect '.data.display_rules=={"countries":["GB","US"],"device_types":["mobile"],"languages":["en"]}' 'display_rules echoed'
expect '.data.timezone=="Europe/London" and (.data.scheduled_at|test($ts)) and (.data.scheduled_end|test($ts))' 'timezone + schedule echoed'
expect '.data.settings|(.utm_source=="newsletter") and (.utm_medium=="email") and (.utm_campaign=="launch") and (.clicks_limit==100) and (.http_status_code==301) and (.sensitive_content==true) and (.forward_query_parameters_is_enabled==true) and (.cloaking_is_enabled==true)' 'settings echoed with their JSON types'
expect '(.data.settings|has("password")|not) and (.data.settings.password_hash|type=="string")' 'password is stored as settings.password_hash (plaintext never echoed)'
FULL_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/links 22a-links-create-full-201

step "P22b. GET /api/v1/links/{id} (full)"
req GET "/api/v1/links/$FULL_ID"
expect_status 200
expect ".data|$LINK_FIELDS and (.display_rules|type==\"object\") and (.settings.password_hash|type==\"string\")" 'full link round-trips'
save GET "/api/v1/links/{id}" 22b-links-get-full-200

step "P22c. PUT /api/v1/links/{id}: new settings, targeting, project cleared"
req PUT "/api/v1/links/$FULL_ID" '{"settings":{"utm_source":"podcast","http_status_code":302},"display_rules":{"countries":["FR"]},"project_id":null}'
expect_status 200
expect '.data.settings.utm_source=="podcast" and (.data.settings|has("utm_medium")|not)' 'settings is REPLACED, not merged (utm_medium gone)'
expect '.data.settings.password_hash|type=="string"' 'password_hash carried forward when password is absent'
expect '.data.display_rules=={"countries":["FR"]}' 'display_rules replaced'
expect '(.data|has("project_id")|not)' 'project_id:null clears the project (key then omitted)'
save PUT "/api/v1/links/{id}" 22c-links-update-full-200

step "P22d. POST /api/v1/links/{id}/duplicate (no body)"
req POST "/api/v1/links/$FULL_ID/duplicate"
expect_status 201
expect ".data|$LINK_FIELDS" 'link fields'
expect ".data.url==\"$SLUG_FULL-copy\"" 'slug is <slug>-copy'
expect '.data.is_enabled==false and .data.clicks==0' 'the copy starts disabled with 0 clicks'
expect ".data.id!=$FULL_ID" 'new id'
DUP_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST "/api/v1/links/{id}/duplicate" 22d-links-duplicate-201

step "P22e. GET /api/v1/links (several, page meta)"
req GET '/api/v1/links?page=1&results_per_page=2'
expect_status 200
expect '.data|type=="array" and length==2' '2 rows at results_per_page=2'
expect '.meta.per_page==2 and .meta.total>=3' 'meta reflects the page size and total'
save GET '/api/v1/links?page=1&results_per_page=2' 22e-links-list-paged-200

step "P22f. DELETE /api/v1/links/{id}"
req DELETE "/api/v1/links/$DUP_ID"
expect_status 200
expect '.data.message|type=="string"' '{message}'
save DELETE "/api/v1/links/{id}" 22f-links-delete-200
req GET "/api/v1/links/$DUP_ID"
expect_status 404
expect "$J_ERR and .error.code==404" '404 envelope after delete'
save GET "/api/v1/links/{id}" 22g-links-get-404

# ── 20. Dashboard (after content exists) ────────────────────────────────────
step "P20a. GET /api/v1/statistics (with content)"
req GET /api/v1/statistics
expect_status 200
expect '.data|keys==["biolinks","domains","links","pixels","projects","qr_codes","total_clicks"]' 'exactly the seven counts'
if jq -e '.data.projects>=1 and .data.domains>=1 and .data.pixels>=1' <<<"$BODY" >/dev/null; then
  note "GET /statistics reflects the new projects/domains/pixels"
else
  note "GET /statistics is cached for 5 min per user and creates do not clear it: counts lag (observed $(jq -c .data <<<"$BODY"))"
fi
save GET /api/v1/statistics 20a-statistics-summary-200

step "P20b. GET /api/v1/statistics/all?type=overview (workspace-wide)"
req GET "/api/v1/statistics/all?type=overview&start_date=$START&end_date=$END"
expect_status 200
expect '.data|type=="array" and length>=1 and all(.[]; (.date|test($date)) and (.pageviews|type=="number") and (.visitors|type=="number"))' '[{date,pageviews,visitors}] across every link'
save GET "/api/v1/statistics/all?type=overview&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD" 20b-statistics-all-overview-200

step "P20c. GET /api/v1/statistics/all?type=country_code"
req GET "/api/v1/statistics/all?type=country_code&start_date=$START&end_date=$END"
expect_status 200
expect '.data==null or (.data|type=="array" and all(.[]; (.label|type=="string") and (.pageviews|type=="number")))' 'null or [{label,pageviews}]'
save GET "/api/v1/statistics/all?type=country_code&..." 20c-statistics-all-country-200

step "P20d. GET /api/v1/resources/recent"
req GET '/api/v1/resources/recent?limit=5'
expect_status 200
expect '.data|type=="array" and length>=1 and length<=5' 'array, newest first, at most limit'
expect '(.|has("meta"))|not' 'no meta (not paginated)'
expect '.data|all(.[]; (.id|type=="number") and (.type|type=="string") and (.url|type=="string") and (.clicks|type=="number") and (.is_enabled|type=="boolean"))' 'rows are Link objects'
if jq -e '.data|any(.[]; .lifecycle_state=="")' <<<"$BODY" >/dev/null; then
  note "resources/recent rows carry lifecycle_state \"\" and last_used_at/lifecycle_state_at \"0001-01-01T00:00:00Z\" (columns not selected): treat as unknown"
fi
save GET '/api/v1/resources/recent?limit=5' 20d-resources-recent-200

step "P20e. GET /api/v1/spotlight?q=<slug prefix>"
req GET "/api/v1/spotlight?q=$SLUG_FULL"
expect_status 200
expect '.data|type=="array" and all(.[]; (.type|IN("biolink","link","user")) and (.id|type=="number") and (.label|type=="string") and (.url|type=="string"))' '[{type,id,label,url}]'
note "spotlight searches every account's enabled links and directory-listed bio pages, not just this workspace"
save GET '/api/v1/spotlight?q=…' 20e-spotlight-200

step "P20f. GET /api/v1/spotlight?q=x (under 2 chars)"
req GET '/api/v1/spotlight?q=x'
expect_status 200
expect '.data==[]' 'short query → [] (not null)'
save GET '/api/v1/spotlight?q=x' 20f-spotlight-short-200

# ── 23. QR codes ────────────────────────────────────────────────────────────
step "P23a. GET /api/v1/qr-codes/types"
req GET /api/v1/qr-codes/types
expect_status 200
expect '.data|type=="array" and length>=1 and all(.[]; (.value|type=="string") and (.label|type=="string") and (.group|type=="string"))' '[{value,label,group}]'
save GET /api/v1/qr-codes/types 23a-qr-codes-types-200

step "P23b. POST /api/v1/qr-codes/generate (preview, not saved)"
req POST /api/v1/qr-codes/generate '{"type":"url","settings":{"url":"https://example.com"},"foreground":"#112233","background":"#ffffff","error_level":"M","size":256}'
expect_status 200
expect '.data|keys==["embedded_data","png"]' 'data is {png, embedded_data}'
expect '.data.png|startswith("data:image/png;base64,")' 'png is a data URL'
expect '.data.embedded_data=="https://example.com"' 'embedded_data is the payload'
save POST /api/v1/qr-codes/generate 23b-qr-codes-generate-200
jq -r '.data.png|sub("^data:image/png;base64,";"")' <<<"$BODY" | base64 -d > "$tmp/tiny.png" 2>/dev/null

step "P23c. POST /api/v1/qr-codes/generate with nothing to encode → 400"
req POST /api/v1/qr-codes/generate '{"type":"url"}'
expect_status 400
expect "$J_ERR and .error.code==400" '400 envelope'
save POST /api/v1/qr-codes/generate 23c-qr-codes-generate-400

step "P23d. POST /api/v1/qr-codes (dynamic: link_id + colours + project)"
req POST /api/v1/qr-codes "$(jq -nc --argjson l "$FULL_ID" --argjson p "$PROJECT_ID" '{name:"Styled QR",type:"url",link_id:$l,project_id:$p,settings:{url:"https://example.com/full"},foreground:"#112233",background:"#ffffff",error_level:"Q"}')"
expect_status 201
expect ".data|$QR_FIELDS" 'qr fields'
expect ".data.link_id==$FULL_ID" 'link_id echoed'
expect '.data.settings._style|type=="object"' 'settings._style present'
QR2_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/qr-codes 23d-qr-codes-create-styled-201

step "P23e. PUT /api/v1/qr-codes/{id} {name}"
req PUT "/api/v1/qr-codes/$QR2_ID" '{"name":"Renamed QR"}'
expect_status 200
expect '.data.name=="Renamed QR" and (.data.qr_code|startswith("data:image/png;base64,"))' 'renamed, image re-rendered'
save PUT "/api/v1/qr-codes/{id}" 23e-qr-codes-update-200

# ── 24. Bio pages and blocks ────────────────────────────────────────────────
SLUG_BIO="ncb-$RUN_ID"
BLOCK_FIELDS='(.id|type=="number") and (.user_id|type=="number") and (.workspace_id|type=="number") and (.link_id|type=="number") and (.type|type=="string") and (.settings|type=="object") and (.clicks|type=="number") and (.is_enabled|type=="boolean") and (.order|type=="number") and (.version|type=="number") and (.created_at|test($ts)) and ((.updated_at==null) or (.updated_at|test($ts)))'

step "P24a. POST /api/v1/biolinks"
req POST /api/v1/biolinks "$(jq -nc --arg s "$SLUG_BIO" '{url:$s,settings:{title:"Contract page",description:"About us"}}')"
expect_status 201
expect '.data|(.id|type=="number") and (.type=="biolink") and (.url|type=="string") and (.settings.title=="Contract page") and (.is_enabled==true)' 'bio page is a Link with type "biolink"'
BIO_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/biolinks 24a-biolinks-create-201

step "P24b. GET /api/v1/biolink-blocks/types"
req GET /api/v1/biolink-blocks/types
expect_status 200
expect '.data|type=="array" and length>=1 and all(.[]; (.type|type=="string") and (.name|type=="string") and (.category|type=="string") and (.icon|type=="string") and (.color|type=="string") and (.has_statistics|type=="boolean") and (.fields|type=="array"))' '[{type,name,category,icon,color,has_statistics,fields}]'
expect '[.data[].fields[]]|all((.name|type=="string") and (.kind|type=="string") and (.label|type=="string"))' 'fields are {name,kind,label,options?}'
save GET /api/v1/biolink-blocks/types 24b-biolink-blocks-types-200

step "P24c. POST /api/v1/biolink-blocks (link, heading, email_collector)"
req POST /api/v1/biolink-blocks "$(jq -nc --argjson l "$BIO_ID" '{link_id:$l,type:"link",location_url:"https://example.com/shop",settings:{name:"Shop",open_in_new_tab:true}}')"
expect_status 201
expect ".data|$BLOCK_FIELDS and (.location_url==\"https://example.com/shop\") and (.version==1)" 'block fields; version starts at 1'
BLOCK1_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/biolink-blocks 24c-biolink-blocks-create-201
req POST /api/v1/biolink-blocks "$(jq -nc --argjson l "$BIO_ID" '{link_id:$l,type:"heading",settings:{heading:"Hello",heading_type:"h2"}}')"
expect_status 201
BLOCK2_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
req POST /api/v1/biolink-blocks "$(jq -nc --argjson l "$BIO_ID" '{link_id:$l,type:"email_collector",settings:{name:"Newsletter"}}')"
expect_status 201
FORM_BLOCK_ID="$(jq -r '.data.id // empty' <<<"$BODY")"

step "P24d. PUT /api/v1/biolink-blocks/{id} with version"
req PUT "/api/v1/biolink-blocks/$BLOCK1_ID" '{"settings":{"name":"Shop now","open_in_new_tab":true},"version":1}'
expect_status 200
expect '.data.settings.name=="Shop now" and .data.version==2' 'updated; version bumped to 2'
save PUT "/api/v1/biolink-blocks/{id}" 24d-biolink-blocks-update-200
req PUT "/api/v1/biolink-blocks/$BLOCK1_ID" '{"settings":{"name":"Stale"},"version":1}'
expect_status 409
expect "$J_ERR and .error.code==409" 'stale version → 409'
save PUT "/api/v1/biolink-blocks/{id}" 24e-biolink-blocks-update-409-stale

step "P24f. POST /api/v1/biolink-blocks/order"
req POST /api/v1/biolink-blocks/order "$(jq -nc --argjson a "$BLOCK2_ID" --argjson b "$BLOCK1_ID" --argjson c "$FORM_BLOCK_ID" '{biolink_block_ids:[$a,$b,$c]}')"
expect_status 200
save POST /api/v1/biolink-blocks/order 24f-biolink-blocks-order-200

step "P24g. GET /api/v1/biolink-blocks?link_id="
req GET "/api/v1/biolink-blocks?link_id=$BIO_ID&page=1&results_per_page=25"
expect_status 200
expect ".data|type==\"array\" and length==3 and all(.[]; $BLOCK_FIELDS)" 'three blocks'
expect "[.data[]|select(.id==$BLOCK2_ID)][0].order < [.data[]|select(.id==$BLOCK1_ID)][0].order" 'order follows the reorder'
save GET '/api/v1/biolink-blocks?link_id={id}' 24g-biolink-blocks-list-200

step "P24h. GET /api/v1/biolinks/{id} → {biolink, blocks}"
req GET "/api/v1/biolinks/$BIO_ID"
expect_status 200
expect '.data|keys==["biolink","blocks"]' 'data is {biolink, blocks}'
expect ".data.biolink.id==$BIO_ID and (.data.blocks|length==3)" 'page + its blocks'
save GET "/api/v1/biolinks/{id}" 24h-biolinks-get-200

step "P24i. PUT /api/v1/biolinks/{id} settings + directory_is_enabled"
req PUT "/api/v1/biolinks/$BIO_ID" '{"settings":{"title":"Contract page","description":"Updated"},"directory_is_enabled":false}'
expect_status 200
expect '.data.settings.description=="Updated" and .data.directory_is_enabled==false' 'settings + directory flag updated'
save PUT "/api/v1/biolinks/{id}" 24i-biolinks-update-200

step "P24j. GET /api/v1/biolinks"
req GET '/api/v1/biolinks?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1 and .[0].type=="biolink"' 'one bio page'
save GET '/api/v1/biolinks?page=1&results_per_page=25' 24j-biolinks-list-200

step "P24k. POST /api/public/biolinks/{slug}/submit (visitor fills the form)"
NO_AUTH=1 req POST "/api/public/biolinks/$SLUG_BIO/submit" "$(jq -nc --argjson b "$FORM_BLOCK_ID" '{biolink_block_id:$b,name:"Grace",email:"grace@example.test"}')"
expect_status 200 201
expect '.data.id|type=="number"' 'submission stored'

# ── 25. Other resource types ────────────────────────────────────────────────
RES_FIELDS='(.id|type=="number") and (.type|type=="string") and (.url|type=="string") and (.settings|type=="object") and (.clicks|type=="number") and (.is_enabled|type=="boolean") and (.created_at|test($ts))'

step "P25a. POST /api/v1/vcards (flat vcard_* fields)"
req POST /api/v1/vcards "$(jq -nc --arg s "ncv-$RUN_ID" '{url:$s,vcard_first_name:"Ada",vcard_last_name:"Lovelace",vcard_email:"ada@example.test",vcard_company:"Engines",vcard_job_title:"Analyst",vcard_phone_numbers:[{value:"+44 20 7946 0000"}],vcard_socials:[{label:"Site",value:"https://example.com"}]}')"
expect_status 201
expect ".data|$RES_FIELDS and (.type==\"vcard\")" 'vcard is a Link with type "vcard"'
expect '.data.settings|(.vcard_first_name=="Ada") and (.vcard_phone_numbers|type=="array") and (.vcard_socials|type=="array") and (.vcard_street=="")' 'fields land in settings; unset ones are ""'
VCARD_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/vcards 25a-vcards-create-201

step "P25b. PUT /api/v1/vcards/{id} (settings replace)"
FULL_VCARD="$(jq -c '.data.settings | .vcard_first_name="Augusta"' <<<"$BODY")"
req PUT "/api/v1/vcards/$VCARD_ID" '{"vcard_first_name":"Ignored"}'
expect_status 200
expect '.data.settings.vcard_first_name=="Ada"' 'flat vcard_* fields are IGNORED on update'
req PUT "/api/v1/vcards/$VCARD_ID" "$(jq -nc --argjson s "$FULL_VCARD" '{settings:$s}')"
expect_status 200
expect '.data.settings.vcard_first_name=="Augusta" and .data.settings.vcard_last_name=="Lovelace"' 'send the whole settings object to update'
save PUT "/api/v1/vcards/{id}" 25b-vcards-update-200

step "P25c. GET /api/v1/vcards/{id}/download → text/vcard"
req GET "/api/v1/vcards/$VCARD_ID/download"
expect_status 200
grep -q '^BEGIN:VCARD' <<<"$BODY" && ok 'body is a vCard' || bad 'vCard body' "$BODY"
grep -qi '^content-type: text/\(x-\)\?vcard' <<<"$HEADERS" && ok "content-type $(grep -i '^content-type' <<<"$HEADERS" | cut -d' ' -f2-)" || note "content-type: $(grep -i '^content-type' <<<"$HEADERS" | cut -d' ' -f2-)"

step "P25d. GET /api/v1/vcards"
req GET '/api/v1/vcards?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'one vcard'
expect "$META" 'meta'
save GET '/api/v1/vcards?page=1&results_per_page=25' 25d-vcards-list-200

step "P25e. POST /api/v1/events (flat event_* fields)"
req POST /api/v1/events "$(jq -nc --arg s "nce-$RUN_ID" '{url:$s,event_name:"Launch night",event_note:"Drinks",event_url:"https://example.com/e",event_location:"London",event_start_datetime:"2030-11-20T18:00",event_end_datetime:"2030-11-20T21:00",event_timezone:"Europe/London"}')"
expect_status 201
expect ".data|$RES_FIELDS and (.type==\"event\")" 'event is a Link with type "event"'
expect '.data.settings|(.event_name=="Launch night") and (.event_start_datetime=="2030-11-20T18:00") and (.event_timezone=="Europe/London")' 'event_* in settings; datetimes are local "YYYY-MM-DDTHH:mm"'
EVENT_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
EVENT_SLUG="$(jq -r '.data.url // empty' <<<"$BODY")"
save POST /api/v1/events 25e-events-create-201

step "P25f. PUT /api/v1/events/{id} {settings}"
req PUT "/api/v1/events/$EVENT_ID" "$(jq -c '{settings: (.data.settings | .event_location="Manchester")}' <<<"$BODY")"
expect_status 200
expect '.data.settings.event_location=="Manchester" and .data.settings.event_name=="Launch night"' 'updated'
save PUT "/api/v1/events/{id}" 25f-events-update-200

step "P25g. GET /api/public/events/{slug}/ics"
NO_AUTH=1 req GET "/api/public/events/$EVENT_SLUG/ics"
expect_status 200
grep -q '^BEGIN:VCALENDAR' <<<"$BODY" && ok 'body is an iCalendar file' || bad 'ICS body' "$BODY"

step "P25h. GET /api/v1/events"
req GET '/api/v1/events?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'one event'
save GET '/api/v1/events?page=1&results_per_page=25' 25h-events-list-200

step "P25i. POST /api/v1/payment-links"
req POST /api/v1/payment-links "$(jq -nc --arg s "ncp-$RUN_ID" '{url:$s,location_url:"https://buy.example.com/checkout/123",settings:{title:"Tip jar"}}')"
expect_status 201
expect ".data|$RES_FIELDS and (.type==\"payment_link\") and (.location_url==\"https://buy.example.com/checkout/123\")" 'payment link is a Link with type "payment_link"'
PAY_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST /api/v1/payment-links 25i-payment-links-create-201
req POST /api/v1/payment-links "$(jq -nc --arg s "ncp2-$RUN_ID" '{url:$s,location_url:"ftp://nope"}')"
expect_status 422
expect "$J_ERR and .error.code==422" 'non-http checkout URL → 422'
save POST /api/v1/payment-links 25j-payment-links-create-422

step "P25k. PUT /api/v1/payment-links/{id}"
req PUT "/api/v1/payment-links/$PAY_ID" '{"is_enabled":false}'
expect_status 200
expect '.data.is_enabled==false' 'disabled'
save PUT "/api/v1/payment-links/{id}" 25k-payment-links-update-200

step "P25l. GET /api/v1/payment-links"
req GET '/api/v1/payment-links?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'one payment link'
save GET '/api/v1/payment-links?page=1&results_per_page=25' 25l-payment-links-list-200

printf 'hello from the native contract run\n' > "$tmp/hello.txt"
printf '<!doctype html><html><body><h1>Contract</h1></body></html>\n' > "$tmp/index.html"

step "P25m. POST /api/v1/files (multipart: url, file)"
req POST /api/v1/files "" -F "url=ncfile-$RUN_ID" -F "file=@$tmp/hello.txt;type=text/plain"
expect_status 201
expect ".data|$RES_FIELDS and (.type==\"file\")" 'file link is a Link with type "file"'
expect '.data.settings|(.file=="hello.txt") and (.file_path|type=="string") and (.force_download_is_enabled==false) and (.sensitive_content==false)' 'settings {file,file_path,force_download_is_enabled,sensitive_content}'
FILE_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST "/api/v1/files (multipart)" 25m-files-create-201

step "P25n. PUT /api/v1/files/{id} (multipart, no new file)"
req PUT "/api/v1/files/$FILE_ID" "" -F "force_download_is_enabled=true"
expect_status 200
expect '.data.settings.force_download_is_enabled==true and .data.settings.file=="hello.txt"' 'flag set, file kept'
save PUT "/api/v1/files/{id} (multipart)" 25n-files-update-200

step "P25o. GET /api/v1/files"
req GET '/api/v1/files?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'one file link'
save GET '/api/v1/files?page=1&results_per_page=25' 25o-files-list-200

step "P25p. POST /api/v1/static (multipart: url, file=index.html)"
req POST /api/v1/static "" -F "url=ncs-$RUN_ID" -F "file=@$tmp/index.html;type=text/html"
expect_status 201
expect ".data|$RES_FIELDS and (.type==\"static\")" 'static page is a Link with type "static"'
STATIC_ID="$(jq -r '.data.id // empty' <<<"$BODY")"
save POST "/api/v1/static (multipart)" 25p-static-create-201

step "P25q. GET /api/v1/static"
req GET '/api/v1/static?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1' 'one static page'
save GET '/api/v1/static?page=1&results_per_page=25' 25q-static-list-200

# ── 26. Account, inbox, uploads, data, workspaces ───────────────────────────
step "P26a. GET /api/v1/account/preferences (never set)"
req GET /api/v1/account/preferences
expect_status 200
expect '.data=={} or .data==null' 'empty object'
save GET /api/v1/account/preferences 26a-account-preferences-200

step "P26b. PUT /api/v1/account/preferences"
req PUT /api/v1/account/preferences '{"default_results_per_page":50,"default_order_type":"DESC","links_auto_copy_link":true}'
expect_status 200
expect '.data=={"default_order_type":"DESC","default_results_per_page":50,"links_auto_copy_link":true}' 'echoes what was stored'
save PUT /api/v1/account/preferences 26b-account-preferences-update-200

step "P26c. POST /api/v1/account/tokens"
req POST /api/v1/account/tokens '{"name":"Shortcuts","scopes":["links:read","links:write"]}'
expect_status 201
expect '.data|(.secret|startswith("cst_")) and (.notice|type=="string") and (.token|type=="object")' '{secret, notice, token}'
expect '.data.token|(.id|type=="number") and (.name=="Shortcuts") and (.scopes==["links:read","links:write"]) and (.last_used_at==null) and (.expires_at==null) and (.revoked_at==null) and (.created_at|test($ts))' 'token fields'
TOKEN_ID="$(jq -r '.data.token.id // empty' <<<"$BODY")"
save POST /api/v1/account/tokens 26c-account-tokens-create-201
req POST /api/v1/account/tokens '{"name":"Bad","scopes":["nope:read"]}'
expect_status 400
save POST /api/v1/account/tokens 26d-account-tokens-create-400

step "P26e. GET /api/v1/account/tokens"
req GET /api/v1/account/tokens
expect_status 200
expect '.data|(.scopes|type=="array" and length>=1) and (.tokens|type=="array" and length==1)' 'data is {scopes:[String], tokens:[Token]} (not a list)'
save GET /api/v1/account/tokens 26e-account-tokens-list-200

step "P26f. DELETE /api/v1/account/tokens/{id}"
req DELETE "/api/v1/account/tokens/$TOKEN_ID"
expect_status 200 204
save DELETE "/api/v1/account/tokens/{id}" 26f-account-tokens-revoke-200

step "P26g. PUT /api/v1/account/password"
req PUT /api/v1/account/password '{"current_password":"wrong-password-1","new_password":"another-pass-123"}'
expect_status 401
expect "$J_ERR and .error.title==\"Current password is incorrect\"" '401 wrong current password'
save PUT /api/v1/account/password 26g-account-password-401
req PUT /api/v1/account/password "$(jq -nc --arg c "$PASSWORD" '{current_password:$c,new_password:"short"}')"
expect_status 400
save PUT /api/v1/account/password 26h-account-password-400
NEW_PASSWORD="$PASSWORD-2"
req PUT /api/v1/account/password "$(jq -nc --arg c "$PASSWORD" --arg n "$NEW_PASSWORD" '{current_password:$c,new_password:$n}')"
expect_status 200
expect '.data.message|type=="string"' '{message}'
save PUT /api/v1/account/password 26i-account-password-200
PASSWORD="$NEW_PASSWORD"
req GET /api/v1/user
expect_status 200
note "the JWT stays valid after a password change"

step "P26j. 2FA: setup → status → verify → disable"
req POST /api/v1/auth/2fa/setup
expect_status 200
expect '.data|(.secret|type=="string") and (.provisioning_url|startswith("otpauth://totp/"))' '{secret, provisioning_url}'
TOTP_SECRET="$(jq -r '.data.secret // empty' <<<"$BODY")"
save POST /api/v1/auth/2fa/setup 26j-2fa-setup-200
req GET /api/v1/auth/2fa/recovery-codes
expect_status 200
expect '.data=={"remaining":0,"twofa_enabled":false}' '{remaining, twofa_enabled}'
save GET /api/v1/auth/2fa/recovery-codes 26k-2fa-status-off-200
totp() { python3 -I -c 'import sys,hmac,hashlib,struct,time,base64
k=base64.b32decode(sys.argv[1]+"="*(-len(sys.argv[1])%8)); c=struct.pack(">Q",int(time.time())//30)
h=hmac.new(k,c,hashlib.sha1).digest(); o=h[-1]&15
print("%06d"%((struct.unpack(">I",h[o:o+4])[0]&0x7fffffff)%1000000))' "$1"; }
if command -v python3 >/dev/null && [[ -n "$TOTP_SECRET" ]]; then
  req POST /api/v1/auth/2fa/verify "{\"code\":\"000000\"}"
  expect_status 400 401 422
  save POST /api/v1/auth/2fa/verify 26l-2fa-verify-bad-code
  req POST /api/v1/auth/2fa/verify "{\"code\":\"$(totp "$TOTP_SECRET")\"}"
  expect_status 200
  expect '.data|(.message|type=="string") and (.recovery_codes|type=="array" and length>=1)' '{message, recovery_codes:[String]}'
  RECOVERY="$(jq -r '.data.recovery_codes[0] // empty' <<<"$BODY")"
  save POST /api/v1/auth/2fa/verify 26m-2fa-verify-200
  req GET /api/v1/auth/2fa/recovery-codes
  expect '.data.twofa_enabled==true and .data.remaining>=1' 'status on, codes remaining'
  save GET /api/v1/auth/2fa/recovery-codes 26n-2fa-status-on-200
  if [[ "${TWOFA_LOGIN:-0}" == 1 ]]; then
    NO_AUTH=1 req POST /api/v1/auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
    expect_status 200
    expect '.data=={"twofa_required":true}' 'challenge: data is exactly {twofa_required:true}'
    save POST /api/v1/auth/login 26o-auth-login-2fa-required-200
    NO_AUTH=1 req POST /api/v1/auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" --arg c "$RECOVERY" '{email:$e,password:$p,recovery_code:$c}')"
    expect_status 200
    expect '(.data.token|type=="string") and (.data.recovery_codes_remaining|type=="number")' 'recovery-code sign-in → {token,user,recovery_codes_remaining}'
    save POST /api/v1/auth/login 26p-auth-login-recovery-code-200
  fi
  req DELETE /api/v1/auth/2fa '{"password":"wrong-password-1"}'
  expect_status 401
  save DELETE /api/v1/auth/2fa 26q-2fa-disable-401
  req DELETE /api/v1/auth/2fa "$(jq -nc --arg p "$PASSWORD" '{password:$p}')"
  expect_status 200
  save DELETE /api/v1/auth/2fa 26r-2fa-disable-200
else
  note "python3 missing: 2FA verify/disable not exercised"
fi

step "P26s. Inbox: /internal-notifications (one seeded with SQL)"
req GET /api/v1/internal-notifications
expect_status 200
expect '.data==null' 'empty inbox is data:null'
expect "$META" 'meta present'
save GET /api/v1/internal-notifications 26s-internal-notifications-empty-200
psql_do "INSERT INTO internal_notifications (user_id, for_who, from_who, icon, title, description, url, is_read) VALUES ($USER_ID, 'user', 'system', 'fas fa-bell', 'Welcome to Cardsite', 'Your workspace is ready.', '/dashboard', false)" >/dev/null || bad "could not seed a notification"
req GET '/api/v1/internal-notifications?page=1&per_page=25'
expect_status 200
expect '.data|type=="array" and length==1 and (.[0]|(.id|type=="number") and (.user_id|type=="number") and (.for_who|type=="string") and (.from_who|type=="string") and (.icon|type=="string") and (.title|type=="string") and (.description|type=="string") and (.url|type=="string") and (.is_read==false) and (.datetime|test($ts)))' '[{id,user_id,for_who,from_who,icon,title,description,url,is_read,datetime}]'
NOTIF_ID="$(jq -r '.data[0].id // empty' <<<"$BODY")"
save GET '/api/v1/internal-notifications?page=1&per_page=25' 26t-internal-notifications-list-200
req GET /api/v1/internal-notifications/unread
expect_status 200
expect '.data|(.unread_count==1) and (.notifications|type=="array" and length==1)' '{notifications:[…]|null, unread_count}'
save GET /api/v1/internal-notifications/unread 26u-internal-notifications-unread-200
req POST "/api/v1/internal-notifications/$NOTIF_ID/read"
expect_status 200
save POST "/api/v1/internal-notifications/{id}/read" 26v-internal-notifications-read-200
req POST /api/v1/internal-notifications/read-all
expect_status 200
save POST /api/v1/internal-notifications/read-all 26w-internal-notifications-read-all-200
req GET /api/v1/internal-notifications/unread
expect '.data.unread_count==0 and .data.notifications==null' 'none unread → notifications:null'
save GET /api/v1/internal-notifications/unread 26x-internal-notifications-unread-empty-200

step "P26y. GET /api/v1/logs (per_page, not results_per_page)"
req GET '/api/v1/logs?page=1&per_page=25'
expect_status 200
expect '.data|type=="array" and length>=1 and all(.[]; (.id|type=="number") and (.user_id|type=="number") and (.type|type=="string") and (.ip|type=="string") and (.datetime|test($ts)))' '[{id,user_id,type,ip,device_type?,os_name?,browser_name?,datetime}]'
save GET '/api/v1/logs?page=1&per_page=25' 26y-logs-200

step "P26z. Uploads: POST (multipart type=image) → list"
if [[ -s "$tmp/tiny.png" ]]; then
  req POST /api/v1/uploads "" -F "type=image" -F "file=@$tmp/tiny.png;type=image/png"
  expect_status 201
  expect '.data|(.upload_id|type=="number") and (.name|type=="string") and (.original_name=="tiny.png") and (.extension=="png") and (.mime_type=="image/png") and (.size|type=="number") and (.type=="image") and (.url|type=="string") and (.created_at|test($ts))' 'upload: id is upload_id (not id)'
  UPLOAD_ID="$(jq -r '.data.upload_id // empty' <<<"$BODY")"
  save POST "/api/v1/uploads (multipart)" 26z1-uploads-create-201
fi
req GET '/api/v1/uploads?page=1&results_per_page=25'
expect_status 200
expect '(.data|type=="array" and length==1) and (.meta|type=="object")' 'one upload'
save GET '/api/v1/uploads?page=1&results_per_page=25' 26z2-uploads-list-200
if [[ -n "${UPLOAD_ID:-}" ]]; then
  req DELETE "/api/v1/uploads/$UPLOAD_ID"
  expect_status 200 204
  save DELETE "/api/v1/uploads/{id}" 26z3-uploads-delete-200
fi

step "P26z4. Data (form submissions)"
req GET '/api/v1/data?page=1&results_per_page=25'
expect_status 200
expect '.data|type=="array" and length==1 and (.[0]|(.id|type=="number") and (.biolink_block_id|type=="number") and (.link_id|type=="number") and (.type=="email_collector") and (.data=={"email":"grace@example.test","name":"Grace"}) and (.datetime|test($ts)))' '[{id,biolink_block_id,link_id,user_id,workspace_id,type,data:{…},datetime}]'
DATA_ID="$(jq -r '.data[0].id // empty' <<<"$BODY")"
save GET '/api/v1/data?page=1&results_per_page=25' 26z4-data-list-200
req GET "/api/v1/data/$DATA_ID"
expect_status 200
expect ".data.id==$DATA_ID" 'one datum'
save GET "/api/v1/data/{id}" 26z5-data-get-200
req DELETE "/api/v1/data/$DATA_ID"
expect_status 200 204
save DELETE "/api/v1/data/{id}" 26z6-data-delete-200

step "P26z7. Workspaces: members, activity, a second workspace and X-Workspace-ID"
req GET /api/v1/workspaces
PERSONAL_WS="$(jq -r '[.data[]|select(.is_personal)][0].workspace_id // empty' <<<"$BODY")"
req GET "/api/v1/workspaces/$PERSONAL_WS/members"
expect_status 200
expect '.data|type=="array" and length==1 and (.[0]|(.workspace_id|type=="number") and (.user_id|type=="number") and (.role=="owner") and (.name|type=="string") and (.email|type=="string") and (.created_at|test($ts)))' '[{workspace_id,user_id,role,name,email,created_at}], no meta'
save GET "/api/v1/workspaces/{id}/members" 26z7-workspaces-members-200
req GET '/api/v1/workspaces/activity?limit=20'
expect_status 200
expect '.data|type=="array" and length>=1 and all(.[]; (.action|type=="string") and (.actor_user_id|type=="number") and (.actor_name|type=="string") and (.at|test($ts)) and ((.subject_type==null) or (.subject_type|type=="string")) and ((.subject_id==null) or (.subject_id|type=="number")) and ((.link_id==null) or (.link_id|type=="number")))' '[{action,actor_user_id,actor_name,at,subject_type?,subject_id?,link_id?}]'
expect '[.data[].action]|all(IN("comment.posted","resource.created","block.created","block.edited","member.joined"))' "actions seen: $(jq -c '[.data[].action]|unique' <<<"$BODY")"
save GET '/api/v1/workspaces/activity?limit=20' 26z8-workspaces-activity-200
req POST /api/v1/workspaces '{"name":"Studio"}'
expect_status 201
expect '.data|(.workspace_id|type=="number") and (.name=="Studio") and (.is_personal==false) and (.role=="owner")' 'workspace created'
WS_ID="$(jq -r '.data.workspace_id // empty' <<<"$BODY")"
save POST /api/v1/workspaces 26z9-workspaces-create-201
req GET '/api/v1/links?page=1&results_per_page=25' "" -H "X-Workspace-ID: $WS_ID"
expect_status 200
expect '.data==null and .meta.total==0' 'X-Workspace-ID scopes lists: the new workspace has no links'
save GET '/api/v1/links (X-Workspace-ID: new)' 26z10-links-list-other-workspace-200
req GET '/api/v1/links' "" -H "X-Workspace-ID: 999999999"
expect_status 403 404
expect "$J_ERR" 'a workspace you are not in → error envelope'
save GET '/api/v1/links (X-Workspace-ID: foreign)' 26z11-links-list-foreign-workspace
req DELETE "/api/v1/workspaces/$WS_ID"
expect_status 200 204
# ── 21 (cont). Organise CRUD: edit, verify, delete ──────────────────────────
# After the links section, which attaches this project, domain and pixel to a
# link; deleting them here also proves a delete with attachments succeeds.

step "P21l. PUT /api/v1/domains/{id} (only the changed fields)"
req PUT "/api/v1/domains/$DOMAIN_ID" '{"scheme":"https","redirect_type":"frame","custom_not_found_url":"https://example.com/404","ssl_is_enabled":true,"force_ssl":true}'
expect_status 200
expect ".data|$OWNED and (.id==$DOMAIN_ID) and (.scheme==\"https\") and (.redirect_type==\"frame\") and (.custom_not_found_url==\"https://example.com/404\") and (.ssl_is_enabled==true) and (.force_ssl==true) and (.forward_parameters==false) and (.is_verified==false)" 'changed fields applied, the rest kept'
expect '.data|has("custom_index_url")|not' 'an unset custom_index_url is left out (omitempty)'
save PUT "/api/v1/domains/{id}" 21l-domains-update-200

step "P21m. POST /api/v1/domains/{id}/verify (no body)"
req POST "/api/v1/domains/$DOMAIN_ID/verify"
expect_status 422 503
if [[ "$STATUS" == 422 ]]; then
  expect ".data.id==$DOMAIN_ID and .data.is_verified==false" '422 carries the domain, recorded as unverified'
  expect '(.error.title|type=="string") and (.error.message|type=="string") and .error.code==422' '422 carries {title,message}: the host and what to point it at'
  save POST "/api/v1/domains/{id}/verify" 21m-domains-verify-422
else
  expect "$J_ERR" '503 (no DOMAIN_VERIFICATION_TARGET): error envelope, not maintenance'
  note "verify answered 503: start the API with DOMAIN_VERIFICATION_TARGET set to capture the 422"
  save POST "/api/v1/domains/{id}/verify" 21m-domains-verify-503
fi

step "P21n. PUT /api/v1/pixels/{id} {name,type,pixel}"
req PUT "/api/v1/pixels/$PIXEL_ID" '{"name":"Ads","type":"linkedin","pixel":"0987654321"}'
expect_status 200
expect ".data|$OWNED and (.id==$PIXEL_ID) and (.type==\"linkedin\") and (.pixel==\"0987654321\")" 'provider and id changed in place'
save PUT "/api/v1/pixels/{id}" 21n-pixels-update-200

step "P21o. PUT /api/v1/projects/{id} {name,color}"
req PUT "/api/v1/projects/$PROJECT_ID" '{"name":"Launch week","color":"#22aa66"}'
expect_status 200
expect '.data.color=="#22aa66"' 'recoloured'
save PUT "/api/v1/projects/{id} {name,color}" 21o-projects-recolour-200

step "P21p. DELETE /api/v1/pixels/{id}, /domains/{id}, /projects/{id}"
req DELETE "/api/v1/pixels/$PIXEL_ID"
expect_status 200
expect '.data.message=="Pixel deleted"' '{message}'
save DELETE "/api/v1/pixels/{id}" 21p-pixels-delete-200
req DELETE "/api/v1/domains/$DOMAIN_ID"
expect_status 200
expect '.data.message=="Domain deleted"' '{message}'
save DELETE "/api/v1/domains/{id}" 21q-domains-delete-200
req DELETE "/api/v1/projects/$PROJECT_ID"
expect_status 200
expect '.data.message=="Project deleted"' '{message}'
save DELETE "/api/v1/projects/{id}" 21r-projects-delete-200
req GET "/api/v1/links/$FULL_ID"
expect_status 200
expect '.data.project_id==null' 'a deleted project leaves its links, unfiled (ON DELETE SET NULL)'
req DELETE "/api/v1/projects/$PROJECT_ID"
expect_status 404
expect "$J_ERR" 'deleting it again → 404 envelope'
else
  PARITY_RAN=0
  step "PARITY skipped"
  note "set PSQL_URL to exercise the parity endpoints (fixtures 20–26)"
fi

# ─── 11. Update profile ─────────────────────────────────────────────────────
step "11. PUT /api/v1/account {name}"
req PUT /api/v1/account '{"name":"Native Contract Renamed"}'
expect_status 200
expect '.data.name=="Native Contract Renamed"' 'response is the updated user'
expect '.data.user_id|type=="number"' 'user shape'
save PUT /api/v1/account 11-account-update-200
req GET /api/v1/user
[[ "$(jq -r '.data.name' <<<"$BODY")" == "Native Contract Renamed" ]] && note "GET /user reflects the rename" \
  || note "GET /user still returns the OLD name (10-min cache not invalidated by PUT /account): use the PUT response"

# ─── 12. Lost password ──────────────────────────────────────────────────────
step "12. POST /api/v1/auth/lost-password"
NO_AUTH=1 req POST /api/v1/auth/lost-password "$(jq -nc --arg e "$EMAIL" '{email:$e}')"
expect_status 200
expect '.data.message|type=="string"' 'data.message string'
save POST /api/v1/auth/lost-password 12-auth-lost-password-200

# ─── 13. Delete account ─────────────────────────────────────────────────────
step "13. DELETE /api/v1/account wrong password → 401"
req DELETE /api/v1/account '{"password":"not-my-password-1"}'
expect_status 401
expect "$J_ERR and .error.code==401" '401 envelope'
save DELETE /api/v1/account 13a-account-delete-401

step "13b. DELETE /api/v1/account missing password → 400"
req DELETE /api/v1/account '{}'
expect_status 400
expect "$J_ERR and .error.code==400" '400 envelope'
save DELETE /api/v1/account 13b-account-delete-400

step "13c. DELETE /api/v1/account right password → 200"
req DELETE /api/v1/account "$(jq -nc --arg p "$PASSWORD" '{password:$p}')"
expect_status 200
expect '.data.message|type=="string"' 'data.message string'
save DELETE /api/v1/account 13c-account-delete-200

step "13d. Old token rejected; login fails"
req GET /api/v1/user
expect_status 401
expect "$J_ERR" 'token for a deleted user → 401 envelope'
save GET /api/v1/user 13d-user-after-delete-401
NO_AUTH=1 req POST /api/v1/auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
expect_status 401
expect "$J_ERR and .error.code==401" 'login after delete → 401'

# ─── 14. Optional: auth limiter ─────────────────────────────────────────────
if [[ "$LIMITER_PROBE" == 1 ]]; then
  step "14. Auth limiter: login until 429"
  for i in $(seq 1 60); do
    NO_AUTH=1 req POST /api/v1/auth/login '{"email":"limiter@example.test","password":"x"}'
    [[ "$STATUS" == 429 ]] && break
  done
  expect_status 429
  expect "$J_ERR and .error.code==429" '429 envelope'
  grep -qi '^retry-after: [0-9]' <<<"$HEADERS" && ok "Retry-After: $(grep -i '^retry-after' <<<"$HEADERS" | cut -d' ' -f2)" || bad 'Retry-After header missing' "$HEADERS"
  save POST /api/v1/auth/login 14-auth-login-429
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
