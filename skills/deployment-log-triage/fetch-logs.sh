#!/usr/bin/env bash
# Acquire a MOHR API token via Entra device-code, then page ApplicationLog into one JSON file.
# Deps: curl, jq. Usage: fetch-logs.sh [baseurl] [--fresh] [--paste] [--selftest]
# Analysis (git correlation + scoring) is done by the SKILL.md prose, not here.
set -euo pipefail

# --- Config -----------------------------------------------------------------
BASEURL="qa-api.myocchealthrecord.dev"        # ponytail: prod baseurl selection is a later phase
TENANT="509fbb62-f2b9-4b62-a975-4bb71278704d" # BodyCare Entra tenant
CLIENT="73416665-cf8c-4d13-babf-aa483f8ba35e" # WsFederation client id == required Entra token `aud`
LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"           # env-overridable: noisy envs need a narrower window
PAGE_SIZE=500
MAX_ROWS="${MAX_ROWS:-5000}"                  # ponytail: safety cap; warns on truncation, never silent. Env-overridable.
FRESH=0
SELFTEST=0
AUTH_MODE=auto                                # auto|az|device — auto prefers az CLI, falls back to device-code

for arg in "$@"; do
  case "$arg" in
    --fresh)        FRESH=1 ;;
    --selftest)     SELFTEST=1 ;;              # dispatched in main, after functions are defined
    --paste)        AUTH_MODE=paste; FRESH=1 ;; # take a browser-copied MOHR JWT from the clipboard
    --az)           AUTH_MODE=az ;;            # force Azure CLI token (workaround for device-code consent error)
    --device-code)  AUTH_MODE=device ;;        # force device-code flow
    --*)            echo "unknown flag: $arg" >&2; exit 2 ;;
    *)              BASEURL="$arg" ;;
  esac
done

SCRATCH="${TMPDIR:-/tmp}/mohr-log-triage"
mkdir -p "$SCRATCH"
SAFEHOST="${BASEURL//[^a-zA-Z0-9]/_}"
TOKEN_CACHE="$SCRATCH/token_$SAFEHOST.jwt"
OUT="$SCRATCH/logs_$SAFEHOST.json"

# --- Helpers ----------------------------------------------------------------
# Decode a JWT payload (base64url, no padding) to JSON on stdout.
jwt_payload() {
  local p="${1#*.}"; p="${p%%.*}"
  local pad=$(( (4 - ${#p} % 4) % 4 ))
  printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null
}

token_valid() { # $1 = jwt; exit 0 if exp is >60s away
  local exp now
  exp=$(jwt_payload "$1" | jq -r '.exp // 0')
  now=$(date +%s)
  [ "$exp" -gt $((now + 60)) ]
}

# --- Entra token -> MOHR token exchange (shared by all auth paths) ----------
# $1 = Entra access token (aud must == $CLIENT). Prints MOHR token, caches it.
exchange_mohr_token() {
  local entra="$1" sub body resp mohr
  sub=$(jwt_payload "$entra" | jq -r '.sub')   # sub -> providerKey
  echo "Exchanging Entra token at ExternalAuthenticate..." >&2
  body=$(jq -n --arg k "$sub" --arg t "$entra" \
          '{authProvider:"WsFederation", providerKey:$k, providerAccessCode:$t}')
  resp=$(curl -s -X POST "https://$BASEURL/api/TokenAuth/ExternalAuthenticate" \
          -H 'accept: application/json' -H 'content-type: application/json' --data "$body")
  # ABP-wrapped: .result.accessToken; fall back to unwrapped shape.
  mohr=$(jq -r '.result.accessToken // .accessToken // empty' <<<"$resp")
  if [ -z "$mohr" ]; then
    echo "Token exchange failed: $(jq -c '{error, result}' <<<"$resp" 2>/dev/null || echo "$resp")" >&2
    exit 1
  fi
  printf '%s' "$mohr" >"$TOKEN_CACHE"
  printf '%s' "$mohr"
}

# --- Clipboard paste auth (reliable path while Entra consent is broken) -----
# Normalize a copied Authorization value to a bare JWT: trim, drop quotes/CR/LF,
# strip a leading "Bearer ".
normalize_paste() {
  printf '%s' "$1" | tr -d '\r\n"'"'" \
    | sed -E 's/^[[:space:]]*([Bb]earer[[:space:]]+)?//; s/[[:space:]]+$//'
}

acquire_via_paste() {
  local raw jwt exp
  if command -v powershell.exe >/dev/null 2>&1; then
    echo "Reading MOHR JWT from clipboard (DevTools > Network > copy the Authorization value)..." >&2
    raw=$(powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null)
  else
    echo "Paste the MOHR JWT and press Enter:" >&2   # ponytail: non-Windows fallback is plain stdin
    IFS= read -r raw
  fi
  jwt=$(normalize_paste "$raw")
  case "$jwt" in
    *.*.*) ;;
    *) echo "Clipboard/input is not a JWT (want header.payload.signature). Copy the Authorization value from DevTools and retry." >&2; exit 1 ;;
  esac
  if ! token_valid "$jwt"; then
    echo "That token is expired or has no readable exp. Copy a fresh one from an active browser session." >&2; exit 1
  fi
  exp=$(jwt_payload "$jwt" | jq -r '.exp')
  printf '%s' "$jwt" >"$TOKEN_CACHE"
  echo "Token cached for $BASEURL (~$(( (exp - $(date +%s)) / 60 )) min remaining)." >&2
  printf '%s' "$jwt"
}

# --- Device-code auth -> Entra token ----------------------------------------
# Note: as of 2026-07 this hits AADSTS90008 (MOHR SSO app lacks Graph consent).
# Kept for envs where consent is fixed; `auto` mode prefers the az CLI path below.
acquire_via_device_code() {
  echo "Requesting device code from Entra..." >&2
  local dc user_code device_code verify interval expires
  dc=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT/oauth2/devicecode" \
        --data-urlencode "client_id=$CLIENT" --data-urlencode "resource=$CLIENT")
  device_code=$(jq -r '.device_code' <<<"$dc")
  user_code=$(jq -r '.user_code' <<<"$dc")
  verify=$(jq -r '.verification_url' <<<"$dc")
  interval=$(jq -r '.interval // 5' <<<"$dc")
  expires=$(jq -r '.expires_in // 900' <<<"$dc")
  if [ "$device_code" = "null" ]; then
    echo "Device-code request failed: $(jq -c '{error,error_description}' <<<"$dc")" >&2; exit 1
  fi

  echo "" >&2
  echo "  >> Open $verify and enter code:  $user_code" >&2
  echo "     (signs in with your current Entra account; waiting for approval...)" >&2
  echo "" >&2

  local deadline=$(( $(date +%s) + expires )) entra="" resp err
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$interval"
    resp=$(curl -s -X POST "https://login.microsoftonline.com/$TENANT/oauth2/token" \
            --data-urlencode "grant_type=device_code" \
            --data-urlencode "client_id=$CLIENT" \
            --data-urlencode "resource=$CLIENT" \
            --data-urlencode "code=$device_code")
    entra=$(jq -r '.access_token // empty' <<<"$resp")
    [ -n "$entra" ] && break
    err=$(jq -r '.error // empty' <<<"$resp")
    case "$err" in
      authorization_pending) ;;                       # keep waiting
      slow_down)             interval=$((interval + 5)) ;;
      "")                    ;;
      consent_required|invalid_grant)
        echo "Device-code auth blocked (likely AADSTS90008 consent). Re-run with --az to use the Azure CLI instead." >&2
        echo "Auth failed: $(jq -c '{error,error_description}' <<<"$resp")" >&2; exit 1 ;;
      *) echo "Auth failed: $(jq -c '{error,error_description}' <<<"$resp")" >&2; exit 1 ;;
    esac
  done
  [ -z "$entra" ] && { echo "Timed out waiting for device-code approval." >&2; exit 1; }

  exchange_mohr_token "$entra"
}

# --- Azure CLI auth (workaround for the device-code consent error) ----------
# Locate az: Git Bash on Windows often lacks it on PATH even when installed.
find_az() {
  if command -v az >/dev/null 2>&1; then command -v az; return 0; fi
  local c
  for c in \
    "/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin/az.cmd" \
    "/c/Program Files (x86)/Microsoft SDKs/Azure/CLI2/wbin/az.cmd"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

acquire_via_az() {
  local az entra
  if ! az=$(find_az); then
    cat >&2 <<'EOF'
Azure CLI (az) is not installed — cannot use the --az workaround.
Install it, then retry:
  winget install --id Microsoft.AzureCLI      (Windows)
  https://learn.microsoft.com/cli/azure/install-azure-cli
After installing, sign in:
  az login --tenant 509fbb62-f2b9-4b62-a975-4bb71278704d
EOF
    exit 3
  fi
  # Logged in?
  if ! "$az" account show >/dev/null 2>&1; then
    echo "Azure CLI is installed but you are not signed in. Run:" >&2
    echo "  az login --tenant $TENANT" >&2
    exit 3
  fi
  echo "Acquiring Entra token via Azure CLI (resource=$CLIENT)..." >&2
  entra=$("$az" account get-access-token --resource "$CLIENT" --tenant "$TENANT" \
            --query accessToken -o tsv 2>"$SCRATCH/az.err") || true
  if [ -z "${entra:-}" ]; then
    echo "az failed to get a token for resource $CLIENT:" >&2
    sed 's/^/  /' "$SCRATCH/az.err" >&2 2>/dev/null || true
    echo "If this is a consent error, an Entra admin must grant the Azure CLI app access to MOHR SSO, or fix the MOHR SSO app's Graph permission." >&2
    exit 1
  fi
  exchange_mohr_token "$entra"
}

get_token() {
  if [ "$FRESH" -eq 0 ] && [ -f "$TOKEN_CACHE" ] && token_valid "$(cat "$TOKEN_CACHE")"; then
    echo "Reusing cached token for $BASEURL." >&2
    cat "$TOKEN_CACHE"
    return 0
  fi
  case "$AUTH_MODE" in
    paste)  acquire_via_paste ;;
    az)     acquire_via_az ;;
    device) acquire_via_device_code ;;
    auto)   if find_az >/dev/null 2>&1; then acquire_via_az; else
              echo "az CLI not found; falling back to device-code auth." >&2
              acquire_via_device_code
            fi ;;
  esac
}

# --- Paginated log fetch ----------------------------------------------------
fetch_logs() {
  local token="$1"
  local window_start skip=0 fetched=0 total=0 earliest="" truncated=0
  # BSD/GNU date differ; try GNU first, then BSD.
  window_start=$(date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
             || date -u -v-"${LOOKBACK_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)

  echo "[]" >"$OUT"
  while :; do
    local body page items count page_earliest
    body=$(jq -n --argjson skip "$skip" --argjson n "$PAGE_SIZE" \
            '{filter:"", sorting:"CreationTime DESC", skipCount:$skip, maxResultCount:$n}')
    page=$(curl -s -X POST "https://$BASEURL/api/services/app/ApplicationLog/RetrieveApplicationLogs" \
            -H 'accept: application/json' -H 'content-type: application/json' \
            -H "authorization: Bearer $token" --data "$body")
    # write page items to a temp file (avoids passing a large page via argv)
    jq -c '.result.items // .items // []' <<<"$page" >"$OUT.page"
    count=$(jq 'length' "$OUT.page")
    total=$(jq -r '.result.totalCount // .totalCount // 0' <<<"$page")
    [ "$count" -eq 0 ] && break

    # merge this page into OUT
    jq -c --slurpfile add "$OUT.page" '. + $add[0]' "$OUT" >"$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    fetched=$((fetched + count))
    page_earliest=$(jq -r 'map(.creationTime) | min' "$OUT.page")
    earliest="$page_earliest"

    # stop conditions
    [ "$(printf '%s\n%s\n' "$page_earliest" "$window_start" | sort | head -1)" = "$page_earliest" ] && break # earliest < window
    [ "$fetched" -ge "$total" ] && break
    if [ "$fetched" -ge "$MAX_ROWS" ]; then truncated=1; break; fi
    skip=$((skip + PAGE_SIZE))
  done

  if [ "$truncated" -eq 1 ]; then
    echo "WARNING: hit MAX_ROWS=$MAX_ROWS cap. Fetched $fetched of $total total; older rows in the ${LOOKBACK_DAYS}d window were NOT retrieved. Raise MAX_ROWS or narrow LOOKBACK_DAYS." >&2
  fi

  jq -n --arg out "$OUT" --argjson fetched "$fetched" --argjson total "$total" \
        --arg window_start "$window_start" --arg earliest "${earliest:-}" --argjson truncated "$truncated" \
        '{output:$out, fetched:$fetched, totalCount:$total, window_start:$window_start, earliest_seen:$earliest, truncated:($truncated==1)}'
}

# --- Self-test (pagination stop-logic) --------------------------------------
selftest() {
  # earliest-before-window comparison is the one bit of logic worth pinning.
  local ws="2026-06-26T00:00:00Z"
  local before="2026-06-20T00:00:00Z" after="2026-06-30T00:00:00Z"
  # "min sorts first" => min < window_start  => stop
  [ "$(printf '%s\n%s\n' "$before" "$ws" | sort | head -1)" = "$before" ] || { echo "selftest FAIL: before-window not detected"; exit 1; }
  [ "$(printf '%s\n%s\n' "$after" "$ws" | sort | head -1)" = "$ws" ]     || { echo "selftest FAIL: after-window misclassified"; exit 1; }
  # jwt padding round-trip
  [ "$(jwt_payload "x.$(printf '{"sub":"s"}' | base64 | tr -d '=' ).y" | jq -r .sub)" = "s" ] || { echo "selftest FAIL: jwt decode"; exit 1; }
  # paste normalization: Bearer prefix, quotes, CRLF, surrounding space all stripped
  [ "$(normalize_paste $'  Bearer "aa.bb.cc"\r\n')" = "aa.bb.cc" ] || { echo "selftest FAIL: paste normalize (bearer)"; exit 1; }
  [ "$(normalize_paste 'aa.bb.cc')" = "aa.bb.cc" ] || { echo "selftest FAIL: paste normalize (bare)"; exit 1; }
  echo "selftest OK"; exit 0
}

# --- Main -------------------------------------------------------------------
[ "$SELFTEST" -eq 1 ] && selftest

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found" >&2; exit 1; }

TOKEN="$(get_token)"
fetch_logs "$TOKEN"
