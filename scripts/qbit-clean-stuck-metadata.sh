#!/usr/bin/env bash
# Delete qBittorrent torrents stuck downloading metadata for too long.
# Intended to be run by qbit-clean-stuck-metadata.service/timer.
set -euo pipefail

NET_GW="172.20.0.3"
QBIT_URL="http://${NET_GW}:8081"
MAX_AGE_SECONDS="${QBIT_METADATA_MAX_AGE_SECONDS:-1800}"

# shellcheck disable=SC1091
. /run/secrets/bootstrap_env

log() { printf '%s\n' "$*"; }

qbit_api() {
  local method="$1" path="$2"; shift 2
  curl --silent --show-error --fail-with-body \
    --variable "apiKey=${QBIT_API_KEY:-}" \
    --expand-header "Authorization: Bearer {{apiKey}}" \
    -X "$method" "$@" "${QBIT_URL}/api/v2/${path}"
}

if [ -z "${QBIT_API_KEY:-}" ]; then
  log "qbit-clean: no QBIT_API_KEY set; skipping"
  exit 0
fi

now="$(date +%s)"
torrents="$(qbit_api GET torrents/info 2>/dev/null || echo '[]')"

hashes="$(echo "$torrents" | jq -r \
  --argjson now "$now" \
  --argjson max_age "$MAX_AGE_SECONDS" '
    .[]
    | select((.state == "metaDL" or .state == "forcedMetaDL"))
    | select((.progress // 0) == 0)
    | select(($now - (.added_on // $now)) >= $max_age)
    | .hash
  ' | paste -sd '|' -)"

if [ -z "$hashes" ]; then
  log "qbit-clean: no metadata-stuck torrents older than ${MAX_AGE_SECONDS}s"
  exit 0
fi

count="$(printf '%s' "$hashes" | awk -F'|' '{print NF}')"
log "qbit-clean: deleting ${count} metadata-stuck torrent(s) older than ${MAX_AGE_SECONDS}s"
qbit_api POST torrents/delete \
  --data-urlencode "hashes=${hashes}" \
  --data-urlencode "deleteFiles=true" >/dev/null
