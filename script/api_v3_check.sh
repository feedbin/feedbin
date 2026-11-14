#!/usr/bin/env bash
#
# Checks API v3 with a bearer token: one line per request, with its status,
# time and a summary of what came back.
#
# Read-only. Every request is a GET. The one thing it changes is the token's
# "last used" time. GET /playlists is left out on purpose: its first call for
# an account migrates that account's podcast subscriptions into playlists.
#
#   ./script/api_v3_check.sh                 # asks for the token, without echoing it
#   TOKEN=fbn_v3_... ./script/api_v3_check.sh
#
# API=https://api.example.test/v3 points it somewhere other than production,
# and CURL_OPTS=-k passes options to curl.
#
# A token created in Settings > Developers has the read and write scopes. A
# token from signing in to one of Feedbin's own apps also has account, which
# /account and /tokens need; with a read write token those two answer 403,
# and that counts as passing.

set -uo pipefail

API="${API:-https://api.feedbin.com/v3}"
TOKEN="${TOKEN:-}"

command -v jq >/dev/null || { echo "This needs jq." >&2; exit 69; }

if [ -z "$TOKEN" ]; then
  printf 'Bearer token: ' >&2
  read -rs TOKEN
  echo >&2
fi

BODY=$(mktemp)
HEADERS=$(mktemp)
trap 'rm -f "$BODY" "$HEADERS"' EXIT

PASSED=0
FAILED=0
STATUS=""

# request <path> [curl options]: leaves the body in $BODY, the headers in
# $HEADERS, and sets STATUS and MILLISECONDS.
request() {
  local path=$1 result
  shift
  # shellcheck disable=SC2086
  result=$(curl -sS ${CURL_OPTS:-} -o "$BODY" -D "$HEADERS" -w '%{http_code} %{time_total}' "$@" "$API$path") || result="000 0"
  STATUS=${result%% *}
  MILLISECONDS=$(awk -v seconds="${result##* }" 'BEGIN { printf "%d", seconds * 1000 }')
}

authorized() {
  local path=$1
  shift
  request "$path" -H "Authorization: Bearer $TOKEN" "$@"
}

header() {
  awk -v name="$1" 'BEGIN { IGNORECASE = 1 } tolower($1) == tolower(name) ":" { sub(/^[^:]*: */, ""); sub(/\r$/, ""); print }' "$HEADERS" | tail -1
}

# A problem document's code and detail, or nothing for another kind of body.
problem() {
  jq -r 'select(type == "object" and .code != null) | "\(.code): \(.detail)"' "$BODY" 2>/dev/null
}

# report <label> <statuses that pass, separated by |> <jq summary>
report() {
  local label=$1 expected=$2 summary=$3 outcome="ok  " text=""
  case "|$expected|" in
    *"|$STATUS|"*) PASSED=$((PASSED + 1)) ;;
    *) outcome="FAIL"; FAILED=$((FAILED + 1)) ;;
  esac
  if [ "$STATUS" -ge 400 ] 2>/dev/null; then
    text=$(problem)
  elif [ -n "$summary" ]; then
    text=$(jq -r "$summary" "$BODY" 2>/dev/null)
  fi
  printf '%s  %s  %5sms  %-44s %s\n' "$outcome" "$STATUS" "$MILLISECONDS" "$label" "$text"
}

echo "API v3 at $API"
echo

request "/subscriptions"
report "no token" "401" ""
[ -n "$(header www-authenticate)" ] || { echo "      the 401 has no WWW-Authenticate header"; FAILED=$((FAILED + 1)); }

request "/subscriptions" -H "Authorization: Bearer fbn_v3_not_a_real_token"
report "a token that does not exist" "401" ""

authorized "/subscriptions"
if [ "$STATUS" != "200" ]; then
  report "GET /subscriptions" "200" ""
  echo
  echo "The token was not accepted, so the rest was skipped."
  exit 1
fi
report "GET /subscriptions" "200" '"\(.data | length) subscriptions"'
etag=$(header etag)
feed_id=$(jq -r '.data[0].feed_id // empty' "$BODY")

authorized "/subscriptions" -H "If-None-Match: $etag"
report "GET /subscriptions, If-None-Match" "304" ""

authorized "/account"
report "GET /account" "200|403" '"\(.email), plan \(.plan.id) (\(.plan.status))"'

authorized "/tokens"
report "GET /tokens" "200|403" '"\(.data | length) tokens"'

authorized "/feeds"
report "GET /feeds" "200" '"\(.data | length) feeds"'

authorized "/tags"
report "GET /tags" "200" '"\(.data | length) tags"'

authorized "/collections"
report "GET /collections" "200" '[.data[] | select(.hidden | not) | .id] | join(", ")'

authorized "/collections/unread/ids"
report "GET /collections/unread/ids" "200" '"\(.data | length) unread"'
etag=$(header etag)

authorized "/collections/unread/ids" -H "If-None-Match: $etag"
report "GET /collections/unread/ids, If-None-Match" "304" ""

authorized "/collections/starred/ids"
report "GET /collections/starred/ids" "200" '"\(.data | length) starred"'

authorized "/collections/unread/entries?limit=3"
report "GET /collections/unread/entries" "200" '"\(.data | length) entries: \(.data[0].title // "untitled" | .[0:50])"'

authorized "/collections/all/entries?limit=3"
report "GET /collections/all/entries" "200" '"\(.data | length) entries"'

authorized "/entries?limit=5"
report "GET /entries" "200" '"\(.data | length) entries: \(.data[0].title // "untitled" | .[0:50])"'
next_cursor=$(jq -r '.page.next_cursor // empty' "$BODY")
arrivals_cursor=$(jq -r '.meta.arrivals_cursor // empty' "$BODY")
edits_cursor=$(jq -r '.meta.edits_cursor // empty' "$BODY")
entry_id=$(jq -r '.data[0].id // empty' "$BODY")

if [ -n "$next_cursor" ]; then
  authorized "/entries?limit=5&cursor=$next_cursor"
  report "GET /entries, the next page" "200" '"\(.data | length) entries"'
fi

if [ -n "$arrivals_cursor" ]; then
  authorized "/entries?cursor=$arrivals_cursor"
  report "GET /entries, arrivals since that page" "200" '"\(.data | length) new"'
  authorized "/entries?cursor=$edits_cursor"
  report "GET /entries, edits since that page" "200" '"\(.data | length) edited"'
else
  echo "FAIL                GET /entries gave no arrivals_cursor"
  FAILED=$((FAILED + 1))
fi

authorized "/entries?limit=20&read=false"
report "GET /entries?read=false" "200" '"\(.data | length) entries"'

if [ -n "$entry_id" ]; then
  authorized "/entries?ids=$entry_id&expand=feed"
  report "GET /entries?ids=$entry_id&expand=feed" "200" '"\(.data[0].kind) from \(.data[0].feed.title // "?"), \(.data[0].content.html | length) characters of HTML"'
fi

if [ -n "$feed_id" ]; then
  authorized "/feeds/$feed_id"
  report "GET /feeds/$feed_id" "200" '.title'
  authorized "/feeds/$feed_id/entries?limit=3"
  report "GET /feeds/$feed_id/entries" "200" '"\(.data | length) entries"'
fi

authorized "/search?query=the&limit=3"
report "GET /search?query=the" "200" '"\(.data | length) results for \(.meta.query)"'

authorized "/saved_searches"
report "GET /saved_searches" "200" '"\(.data | length) saved searches"'

authorized "/actions"
report "GET /actions" "200" '"\(.data | length) actions"'

authorized "/subscriptions.opml"
report "GET /subscriptions.opml" "200" ""

authorized "/entries?cursor=zz"
report "a cursor that is not one of ours" "400" ""

authorized "/no/such/thing"
report "a path that does not exist" "404" ""

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
