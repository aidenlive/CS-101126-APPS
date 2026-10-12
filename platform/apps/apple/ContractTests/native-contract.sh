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
# every string that looks like a JWT becomes "<redacted-jwt>".
save() {
  [[ "$WRITE_FIXTURES" == 1 ]] || return 0
  mkdir -p "$FIXTURE_DIR"
  jq --arg s "$STATUS" --arg m "$1" --arg p "$2" '
      walk(if type=="string" and test("^eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$") then "<redacted-jwt>" else . end)
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
expect 'all(.data[]; ((.monthly_price==null) or (.monthly_price|type=="number")) and ((.annual_price==null) or (.annual_price|type=="number")))' 'monthly_price/annual_price number or ABSENT (omitempty *float64)'expect '[.data[]|select(.name=="Free")][0].settings.custom_slugs_limit==1' 'Free plan custom_slugs_limit == 1'
save GET /api/v1/plans 10b-plans-200

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
