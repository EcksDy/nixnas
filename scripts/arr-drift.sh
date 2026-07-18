#!/usr/bin/env bash
# ================================================================
# arr-drift — snapshot arr config via API for git-diff review.
#
# Polls each app's settings (indexers, quality profiles, download
# clients, root folders, media management) and writes NORMALIZED,
# SECRET-SCRUBBED JSON to $OUT. `git diff` then surfaces UI drift
# from the declared/enforced config.
#
# Sourced env: /run/secrets/bootstrap_env (API keys).
# Output dir:  $OUT (default /etc/nixos/state-snapshots)
# ================================================================
set -euo pipefail

OUT="${OUT:-/etc/nixos/state-snapshots}"
mkdir -p "$OUT"

# shellcheck disable=SC1091
. /run/secrets/bootstrap_env

log() { printf '[drift] %s\n' "$*"; }

# jq filter: drop volatile/secret fields, sort deterministically.
# Removes apiKey/password/token-ish fields recursively.
SCRUB='
  def scrub:
    walk(
      if type=="object" then
        with_entries(
          select(.key |
            ascii_downcase |
            test("apikey|password|token|secret|cookie") | not)
        )
      else . end);
  scrub
'

# fetch + normalize one endpoint to a stable file
snap() {
  local app="$1" url="$2" key="$3" ep="$4" apiver="${5:-v3}"
  local dest="$OUT/${app}.${ep//\//_}.json"
  if curl -fsS -H "X-Api-Key: ${key}" "${url}/api/${apiver}/${ep}" 2>/dev/null \
      | jq -S "${SCRUB}" > "$dest.tmp" 2>/dev/null; then
    mv -f "$dest.tmp" "$dest"
    log "  ${app}/${ep}"
  else
    rm -f "$dest.tmp"
    log "  ${app}/${ep} unreachable, skipped"
  fi
}

snap_arr() {
  local app="$1" url="$2" key="$3"
  [ -n "$key" ] || { log "${app}: no api key, skip"; return 0; }
  snap "$app" "$url" "$key" "indexer"
  snap "$app" "$url" "$key" "downloadclient"
  snap "$app" "$url" "$key" "rootfolder"
  snap "$app" "$url" "$key" "qualityprofile"
  snap "$app" "$url" "$key" "customformat"
}

snap_arr "sonarr"       "http://172.20.0.10:8989" "${SONARR_API_KEY:-}"
snap_arr "sonarr-anime" "http://172.20.0.11:8989" "${SONARR_ANIME_API_KEY:-}"
snap_arr "radarr"       "http://172.20.0.12:7878" "${RADARR_API_KEY:-}"
snap_arr "lidarr"       "http://172.20.0.13:8686" "${LIDARR_API_KEY:-}"

# prowlarr (v1): indexers + apps
if [ -n "${PROWLARR_API_KEY:-}" ]; then
  snap "prowlarr" "http://172.20.0.3:9696" "$PROWLARR_API_KEY" "indexer" "v1"
  snap "prowlarr" "http://172.20.0.3:9696" "$PROWLARR_API_KEY" "applications" "v1"
fi

log "drift snapshot written to $OUT (review with: git -C \"$(dirname "$OUT")\" diff state-snapshots/)"
