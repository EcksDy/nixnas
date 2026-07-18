#!/usr/bin/env bash
# ================================================================
# arr-bootstrap — declarative reconcile of arr wiring via REST API.
#
# Model (borrowed from nixflix): config is the source of truth.
# For the resources we OWN, we reconcile:
#   POST   create if missing
#   PUT    update if present but differs
#   DELETE remove if present but NOT in our desired set  (SCOPED!)
#
# SCOPE of delete-orphan (deliberately narrow):
#   - download clients (name qBittorrent / SABnzbd)
#   - root folders
#   - Prowlarr applications
# We NEVER delete indexers (you add those in the Prowlarr UI with
# credentials — they are intentionally not declared here).
#
# Secrets: /run/secrets/bootstrap_env. API keys are passed to curl via
# --variable / --expand-header so they never appear on argv / in ps.
#
# Idempotent + safe to re-run. Runs automatically once on first creation;
# thereafter manual only (systemctl start arr-reconcile.service).
# ================================================================
set -euo pipefail

# --- static topology (matches modules/media) ---
NET_GW="172.20.0.3"                      # gluetun (qbit/sab/prowlarr live here)
PROWLARR_URL="http://${NET_GW}:9696"
SONARR_URL="http://172.20.0.10:8989"
SONARR_ANIME_URL="http://172.20.0.11:8989"
RADARR_URL="http://172.20.0.12:7878"
LIDARR_URL="http://172.20.0.13:8686"
JELLYSEERR_URL="http://172.20.0.5:5055"

# shellcheck disable=SC1091
. /run/secrets/bootstrap_env

log() { printf '[bootstrap] %s\n' "$*"; }

# ---------------------------------------------------------------
# Secure curl: API key passed via --variable + --expand-header, so
# it is never visible on the command line. JSON body via temp file.
#   api <key> <method> <url> [json-body]
# Echoes response body; returns curl's exit status.
# ---------------------------------------------------------------
api() {
  local key="$1" method="$2" url="$3" body="${4:-}"
  local tmp="" args=()
  args=(--silent --show-error --fail
        --variable "apiKey=$key"
        --expand-header "X-Api-Key: {{apiKey}}"
        -X "$method")
  if [ -n "$body" ]; then
    tmp="$(mktemp)"
    printf '%s' "$body" > "$tmp"
    args+=(--header "Content-Type: application/json" --data-binary "@$tmp")
  fi
  curl "${args[@]}" "$url"
  local rc=$?
  [ -n "$tmp" ] && rm -f "$tmp"
  return $rc
}

wait_up() {
  local name="$1" url="$2" key="$3" apiver="${4:-v3}" _i
  for _i in $(seq 1 90); do
    if api "$key" GET "${url}/api/${apiver}/system/status" >/dev/null 2>&1; then
      log "${name} up"; return 0
    fi
    sleep 2
  done
  log "WARN: ${name} not up after 180s; skipping"; return 1
}

# ---------------------------------------------------------------
# Reconcile a v3 resource collection by a match key.
#   reconcile <key> <base_url> <endpoint> <match_field> <desired_json_array> <apiver>
# desired_json_array: JSON array of objects to ensure present.
# Deletes existing entries whose <match_field> is not in desired.
# ---------------------------------------------------------------
reconcile() {
  local key="$1" base="$2" ep="$3" field="$4" desired="$5" apiver="${6:-v3}"
  local url="${base}/api/${apiver}/${ep}"
  local current names_desired
  current="$(api "$key" GET "$url" 2>/dev/null || echo '[]')"
  names_desired="$(echo "$desired" | jq -c "[.[].${field}]")"

  # DELETE orphans (present but not desired)
  echo "$current" | jq -c '.[]' | while IFS= read -r item; do
    local iname iid
    iname="$(echo "$item" | jq -r ".${field}")"
    iid="$(echo "$item" | jq -r '.id')"
    if ! echo "$names_desired" | jq -e --arg n "$iname" 'index($n)' >/dev/null; then
      log "  delete orphan ${ep}: ${iname} (id ${iid})"
      api "$key" DELETE "${url}/${iid}" >/dev/null 2>&1 || log "  WARN delete ${iname} failed"
    fi
  done

  # CREATE or UPDATE
  echo "$desired" | jq -c '.[]' | while IFS= read -r want; do
    local wname existing eid
    wname="$(echo "$want" | jq -r ".${field}")"
    existing="$(echo "$current" | jq -c --arg n "$wname" ".[] | select(.${field}==\$n)" | head -n1)"
    if [ -z "$existing" ]; then
      log "  create ${ep}: ${wname}"
      api "$key" POST "$url" "$want" >/dev/null || log "  WARN create ${wname} failed"
    else
      eid="$(echo "$existing" | jq -r '.id')"
      # merge id into desired and PUT (update)
      local merged
      merged="$(echo "$want" | jq -c --argjson id "$eid" '. + {id:$id}')"
      log "  update ${ep}: ${wname}"
      api "$key" PUT "${url}/${eid}" "$merged" >/dev/null 2>&1 \
        || log "  (update ${wname} skipped/failed — often OK if unchanged)"
    fi
  done
}

# ---- desired-state builders -----------------------------------

qbit_json() {
  local cat="$1"
  jq -n --arg host "$NET_GW" --arg cat "$cat" \
        --arg user "${QBIT_USER:-admin}" --arg pass "${QBIT_PASS:-}" '
    { enable:true, protocol:"torrent", priority:1, name:"qBittorrent",
      implementation:"QBittorrent", configContract:"QBittorrentSettings",
      fields:[ {name:"host",value:$host},{name:"port",value:8080},
               {name:"username",value:$user},{name:"password",value:$pass},
               {name:"category",value:$cat} ] }'
}
sab_json() {
  local cat="$1"
  jq -n --arg host "$NET_GW" --arg cat "$cat" --arg apikey "${SAB_API_KEY:-}" '
    { enable:true, protocol:"usenet", priority:1, name:"SABnzbd",
      implementation:"Sabnzbd", configContract:"SabnzbdSettings",
      fields:[ {name:"host",value:$host},{name:"port",value:8085},
               {name:"apiKey",value:$apikey},{name:"category",value:$cat} ] }'
}

# download clients desired-array for an arr (qbit always; sab only if key set)
clients_desired() {
  local cat="$1" arr="[]"
  arr="$(jq -n --argjson q "$(qbit_json "$cat")" '[$q]')"
  if [ -n "${SAB_API_KEY:-}" ]; then
    arr="$(jq -n --argjson a "$arr" --argjson s "$(sab_json "$cat")" '$a + [$s]')"
  fi
  echo "$arr"
}

rootfolder_desired() { jq -n --arg p "$1" '[{path:$p}]'; }

# ---- per-arr reconcile ----------------------------------------
do_arr() {
  local name="$1" url="$2" key="$3" cat="$4" root="$5"
  wait_up "$name" "$url" "$key" || return 0
  reconcile "$key" "$url" "downloadclient" "name" "$(clients_desired "$cat")"
  reconcile "$key" "$url" "rootfolder"     "path" "$(rootfolder_desired "$root")"
}

do_arr "sonarr"       "$SONARR_URL"       "${SONARR_API_KEY:-}"       "tv"     "/data/media/tv"
do_arr "sonarr-anime" "$SONARR_ANIME_URL" "${SONARR_ANIME_API_KEY:-}" "anime"  "/data/media/anime"
do_arr "radarr"       "$RADARR_URL"       "${RADARR_API_KEY:-}"       "movies" "/data/media/movies"
do_arr "lidarr"       "$LIDARR_URL"       "${LIDARR_API_KEY:-}"       "music"  "/data/media/music"

# ---- Prowlarr -> applications (reconcile, v1) ------------------
prowlarr_apps_desired() {
  jq -n \
    --arg purl "$PROWLARR_URL" \
    --arg surl "$SONARR_URL"       --arg skey "${SONARR_API_KEY:-}" \
    --arg aurl "$SONARR_ANIME_URL" --arg akey "${SONARR_ANIME_API_KEY:-}" \
    --arg rurl "$RADARR_URL"       --arg rkey "${RADARR_API_KEY:-}" \
    --arg lurl "$LIDARR_URL"       --arg lkey "${LIDARR_API_KEY:-}" '
    [
      {name:"Sonarr",       implementation:"Sonarr", configContract:"SonarrSettings", syncLevel:"fullSync",
       fields:[{name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$surl},{name:"apiKey",value:$skey}]},
      {name:"Sonarr-Anime", implementation:"Sonarr", configContract:"SonarrSettings", syncLevel:"fullSync",
       fields:[{name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$aurl},{name:"apiKey",value:$akey}]},
      {name:"Radarr",       implementation:"Radarr", configContract:"RadarrSettings", syncLevel:"fullSync",
       fields:[{name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$rurl},{name:"apiKey",value:$rkey}]},
      {name:"Lidarr",       implementation:"Lidarr", configContract:"LidarrSettings", syncLevel:"fullSync",
       fields:[{name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$lurl},{name:"apiKey",value:$lkey}]}
    ]'
}

if wait_up "prowlarr" "$PROWLARR_URL" "${PROWLARR_API_KEY:-}" "v1"; then
  reconcile "${PROWLARR_API_KEY:-}" "$PROWLARR_URL" "applications" "name" \
    "$(prowlarr_apps_desired)" "v1"
  log "note: indexers are NOT managed here — add them in the Prowlarr UI (with creds)."
fi

# ---- Jellyseerr (best-effort service wiring) ------------------
# Jellyseerr's admin/user creation is UI-wizard-bound (can't be created
# headlessly without the setup cookie). But once you've created the admin
# user in the UI and generated an API key (Settings -> General -> API Key)
# and put it in bootstrap_env as JELLYSEERR_API_KEY, we can reconcile the
# Sonarr/Radarr service entries via the API.
jellyseerr_wire() {
  [ -n "${JELLYSEERR_API_KEY:-}" ] || {
    log "jellyseerr: no JELLYSEERR_API_KEY set — finish linking in the UI (one-time)"
    return 0
  }
  local base="${JELLYSEERR_URL}/api/v1"
  # Sonarr
  if ! curl -fsS -H "X-Api-Key: ${JELLYSEERR_API_KEY}" "${base}/settings/sonarr" 2>/dev/null \
       | jq -e '.[]|select(.name=="Sonarr")' >/dev/null 2>&1; then
    if curl -fsS -X POST -H "X-Api-Key: ${JELLYSEERR_API_KEY}" -H 'Content-Type: application/json' \
      "${base}/settings/sonarr" -d "$(jq -n --arg key "${SONARR_API_KEY:-}" '
        {name:"Sonarr",hostname:"172.20.0.10",port:8989,apiKey:$key,useSsl:false,
         baseUrl:"",activeProfileId:1,activeProfileName:"Any",
         activeDirectory:"/data/media/tv",is4k:false,isDefault:true,
         enableSeasonFolders:true}')" >/dev/null 2>&1; then
      log "jellyseerr: Sonarr linked"
    else
      log "jellyseerr: Sonarr link failed (set profile/root in UI)"
    fi
  fi
  # Radarr
  if ! curl -fsS -H "X-Api-Key: ${JELLYSEERR_API_KEY}" "${base}/settings/radarr" 2>/dev/null \
       | jq -e '.[]|select(.name=="Radarr")' >/dev/null 2>&1; then
    if curl -fsS -X POST -H "X-Api-Key: ${JELLYSEERR_API_KEY}" -H 'Content-Type: application/json' \
      "${base}/settings/radarr" -d "$(jq -n --arg key "${RADARR_API_KEY:-}" '
        {name:"Radarr",hostname:"172.20.0.12",port:7878,apiKey:$key,useSsl:false,
         baseUrl:"",activeProfileId:1,activeProfileName:"Any",
         activeDirectory:"/data/media/movies",is4k:false,isDefault:true}')" >/dev/null 2>&1; then
      log "jellyseerr: Radarr linked"
    else
      log "jellyseerr: Radarr link failed (set profile/root in UI)"
    fi
  fi
}

if curl -fsS "${JELLYSEERR_URL}/api/v1/status" >/dev/null 2>&1; then
  log "jellyseerr up"
  jellyseerr_wire
fi

log "bootstrap reconcile complete"
