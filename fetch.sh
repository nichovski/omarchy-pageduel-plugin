#!/usr/bin/env bash
# Fetch current live-visitor counts from the PageDuel v1 Read API and write
# them to a JSON file the bar widget watches.
# Uses stored credentials from ~/.config/omarchy/pageduel/credentials.env
#
# Quota-friendly behaviour: a 429 (daily API budget exceeded) or any other
# error backs off and is not retried until the backoff elapses, so a
# misconfigured or rate-limited key can't hot-loop the API.

set -euo pipefail

CRED_FILE="$HOME/.config/omarchy/pageduel/credentials.env"
OUTPUT_FILE="$HOME/.config/omarchy/pageduel/live_visitors.json"

ERROR_BACKOFF=120       # seconds to wait after a transient/network error
AUTH_BACKOFF=3600       # seconds to wait after an auth/plan error (won't fix itself)
DEFAULT_RETRY=300       # fallback when Retry-After is missing/unparseable on a 429

now() { date +%s; }

write_state() { # <json-string>
  printf '%s\n' "$1" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
}

write_error() { # <message> [backoff-seconds]
  local msg="$1" backoff="${2:-$ERROR_BACKOFF}" t
  t=$(( $(now) + backoff ))
  write_state "$(jq -n --arg e "$msg" --argjson t "$t" '{error: $e, retry_at: $t}')"
  exit 0
}

mkdir -p "$(dirname "$CRED_FILE")"

if [[ ! -f "$CRED_FILE" ]]; then
  write_error "Not configured. Run: python3 ~/.config/omarchy/plugins/nichovski.pageduel-live-visitors/setup.py" "$AUTH_BACKOFF"
fi

source "$CRED_FILE"

if [[ -z "${PAGEDUEL_API_KEY:-}" ]]; then
  write_error "No API key saved. Run: python3 ~/.config/omarchy/plugins/nichovski.pageduel-live-visitors/setup.py" "$AUTH_BACKOFF"
fi

API_BASE="${PAGEDUEL_API_BASE:-https://pageduel.com/api/v1}"

NOW=$(now)

# Inside a back-off window? Do not touch the API at all.
if [[ -f "$OUTPUT_FILE" ]]; then
  RETRY_AT=$(jq -r '.retry_at // 0' "$OUTPUT_FILE" 2>/dev/null || echo 0)
  if [[ "$RETRY_AT" =~ ^[0-9]+$ ]] && (( RETRY_AT > NOW )); then
    exit 0
  fi
fi

HDRS=$(mktemp)
trap 'rm -f "$HDRS"' EXIT

RESPONSE=$(curl -s -D "$HDRS" -w "\n%{http_code}" \
  -H "Authorization: Bearer $PAGEDUEL_API_KEY" \
  "$API_BASE/live" 2>/dev/null || printf '\n000')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" == "401" ]]; then
  write_error "PageDuel API key is missing, invalid or revoked. Run setup.py to reconfigure." "$AUTH_BACKOFF"
fi

if [[ "$HTTP_CODE" == "402" ]]; then
  write_error "Your PageDuel plan doesn't include API access." "$AUTH_BACKOFF"
fi

if [[ "$HTTP_CODE" == "429" ]]; then
  RETRY_AFTER=$(awk 'BEGIN{IGNORECASE=1} /^retry-after:/ {gsub(/\r/,"",$2); print $2}' "$HDRS" | tail -n1)
  [[ "$RETRY_AFTER" =~ ^[0-9]+$ ]] || RETRY_AFTER=$DEFAULT_RETRY
  write_error "PageDuel API daily limit reached — try a longer poll interval." "$RETRY_AFTER"
fi

if [[ "$HTTP_CODE" != "200" ]]; then
  write_error "PageDuel API error (HTTP $HTTP_CODE)"
fi

if ! echo "$BODY" | jq -e '.data.visitors' >/dev/null 2>&1; then
  write_error "Unexpected response from PageDuel API"
fi

write_state "$(echo "$BODY" | jq --argjson fetched "$NOW" '{
  visitors: .data.visitors,
  sites: (.data.sites // []),
  windowSeconds: (.meta.windowSeconds // 300),
  fetched_at: $fetched
}')"
