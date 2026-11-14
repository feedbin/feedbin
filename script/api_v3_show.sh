#!/usr/bin/env bash
#
# Shows what API v3 answers, pretty-printed: the status, the headers worth
# seeing, and the JSON body.
#
# Read-only. Every request is a GET. The one thing it changes is the token's
# "last used" time.
#
#   ./script/api_v3_show.sh                          # a tour of the main endpoints
#   ./script/api_v3_show.sh '/entries?limit=2' /tags # only these paths
#   FULL=1 ./script/api_v3_show.sh /subscriptions    # nothing shortened
#
# It asks for the token without echoing it, or takes it from TOKEN.
# API=https://api.example.test/v3 points it somewhere other than production,
# and CURL_OPTS=-k passes options to curl.
#
# To keep a response readable, a list is cut to its first ITEMS items (2) and
# a string to its first CHARACTERS characters (300), and each cut says how
# much it left out. FULL=1 prints the body exactly as it arrived.

set -uo pipefail

API="${API:-https://api.feedbin.com/v3}"
TOKEN="${TOKEN:-}"
ITEMS="${ITEMS:-2}"
CHARACTERS="${CHARACTERS:-300}"

command -v jq >/dev/null || { echo "This needs jq." >&2; exit 69; }

if [ -z "$TOKEN" ]; then
  printf 'Bearer token: ' >&2
  read -rs TOKEN
  echo >&2
fi

BODY=$(mktemp)
HEADERS=$(mktemp)
trap 'rm -f "$BODY" "$HEADERS"' EXIT

if [ -t 1 ]; then
  COLOR="-C"; BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
else
  COLOR="-M"; BOLD=""; DIM=""; RESET=""
fi

# Lists and strings cut short, each cut saying what it left out.
SHORTEN='
def shorten($items; $characters):
  if type == "array" then
    (if length > $items then (.[0:$items] | map(shorten($items; $characters))) + ["… \(length - $items) more"]
     else map(shorten($items; $characters)) end)
  elif type == "object" then with_entries(.value |= shorten($items; $characters))
  elif type == "string" and length > $characters then .[0:$characters] + "… (\(length - $characters) more characters)"
  else . end;
shorten($items; $characters)'

header() {
  awk -v name="$1" 'tolower($1) == tolower(name) ":" { sub(/^[^:]*: */, ""); sub(/\r$/, ""); print }' "$HEADERS" | tail -1
}

show() {
  local path=$1 result status milliseconds name value
  # shellcheck disable=SC2086
  result=$(curl -sS ${CURL_OPTS:-} -o "$BODY" -D "$HEADERS" -w '%{http_code} %{time_total}' -H "Authorization: Bearer $TOKEN" "$API$path") || result="000 0"
  status=${result%% *}
  milliseconds=$(awk -v seconds="${result##* }" 'BEGIN { printf "%d", seconds * 1000 }')

  echo "${BOLD}GET $path${RESET}  ${status}  ${DIM}${milliseconds}ms${RESET}"
  for name in content-type etag cache-control www-authenticate retry-after; do
    value=$(header "$name")
    [ -n "$value" ] && echo "${DIM}$name: $value${RESET}"
  done

  if [ ! -s "$BODY" ]; then
    echo "${DIM}(no body)${RESET}"
  elif ! jq -e . "$BODY" >/dev/null 2>&1; then
    head -c 1500 "$BODY"
    echo
    echo "${DIM}(not JSON; the first 1,500 bytes of $(wc -c < "$BODY" | tr -d ' '))${RESET}"
  elif [ "${FULL:-}" = "1" ]; then
    jq $COLOR . "$BODY"
  else
    jq $COLOR --argjson items "$ITEMS" --argjson characters "$CHARACTERS" "$SHORTEN" "$BODY"
  fi
  echo
}

echo "API v3 at $API"
echo

if [ "$#" -gt 0 ]; then
  for path in "$@"; do
    show "$path"
  done
  exit 0
fi

show "/account"
show "/subscriptions"
show "/feeds"
show "/tags"
show "/collections"
show "/collections/unread/ids"
show "/entries?limit=1&expand=feed"
show "/collections/unread/entries?limit=1"
show "/search?query=the&limit=1"
show "/saved_searches"
show "/actions"
show "/tokens"
show "/entries?cursor=zz"
