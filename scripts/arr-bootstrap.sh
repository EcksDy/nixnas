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
SEERR_URL="http://172.20.0.5:5055"
EXTERNAL_DOMAIN="${NIXNAS_DOMAIN:?NIXNAS_DOMAIN is not set}"

# shellcheck disable=SC1091
. /run/secrets/bootstrap_env

log() { printf '%s\n' "$*"; }

summarize_error() {
  # Keep curl/servarr validation output readable in journald.
  local input
  input="$(cat)"
  if printf '%s' "$input" | jq -er 'if type == "array" then map((.propertyName // .field // "error") + ": " + (.errorMessage // .message // tostring)) | join("; ") elif type == "object" then (.message // .errorMessage // tostring) else tostring end' 2>/dev/null; then
    return 0
  fi
  printf '%s' "$input" | sed ':a;N;$!ba;s/\n/ /g'
}

# ---------------------------------------------------------------
# Secure curl: API key passed via --variable + --expand-header, so
# it is never visible on the command line. JSON body via temp file.
#   api <key> <method> <url> [json-body]
# Echoes response body; returns curl's exit status.
# ---------------------------------------------------------------
api() {
  local key="$1" method="$2" url="$3" body="${4:-}"
  local tmp="" args=()
  args=(--silent --show-error --fail-with-body
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

qbit_api() {
  local method="$1" path="$2"; shift 2
  curl --silent --show-error --fail-with-body \
    --variable "apiKey=${QBIT_API_KEY:-}" \
    --expand-header "Authorization: Bearer {{apiKey}}" \
    -X "$method" "$@" "http://${NET_GW}:8081/api/v2/${path}"
}

qbit_wait_up() {
  local _i
  [ -n "${QBIT_API_KEY:-}" ] || { log "qbit: no QBIT_API_KEY set — skipping qBit path/category setup"; return 1; }
  for _i in $(seq 1 60); do
    if qbit_api GET app/version >/dev/null 2>&1; then
      log "qbit up"; return 0
    fi
    sleep 2
  done
  log "WARN: qbit not up after 120s; skipping qBit path/category setup"; return 1
}

qbit_set_prefs() {
  local excluded prefs
  excluded="$(cat <<'EOF'
*.lnk
*.pif
*.scr
*.jpeg
*.bat
*.com
*.txt
*.nfo
*.doc
*.docx
*.pdf
*.rtf
*.js
*.py
*.html
*.css
*.php
*.sh
*.zip
*.rar
*.7z
*.tar
*.gz
*.iso
*.img
*.exe
*.msi
*.apk
*.dmg
*.dll
*.sys
*.ini
*.dat
*.tmp
*.sub
*.sfv
*.zipx
*.jpg
*.idx
*.png
*.sup
*.cmd
*.vbs
*.reg
*.xml
*.sqlite
*.website
*.ps1
*.cpl
*.hta
*.jar
*.vb
*.vbe
*.jse
*.wsf
*.msc
*.gadget
*.ocx
*.drv
*.bin
*.c
*.cpp
*.h
*.vbproj
*.csproj
*.cab
*.bz2
*.xz
*.tgz
*.txz
*.apkx
*.ipa
*.wim
*.xpi
*.ear
*.war
*.m4b
*.m4p
*.m4r
*.aac
*.cue
*.m3u
*.pls
*.asx
*.thm
*.md5
*.sha1
*.sha256
*.par
*.par2
*.torrent
*.log
*.bak
*.old
*.temp
*.chm
*.hlp
*.xps
*.ics
*.arj
*.contact
*sample.mkv
*sample.avi
*sample.mp4
EOF
)"
  prefs="$(jq -nc --arg excluded "$excluded" '{
    save_path:"/data/torrents/",
    temp_path:"/data/torrents/incomplete/",
    temp_path_enabled:true,
    torrent_content_layout:"Subfolder",
    use_category_paths_in_manual_mode:true,
    upnp:false,
    bypass_local_auth:true,
    bypass_auth_subnet_whitelist_enabled:true,
    bypass_auth_subnet_whitelist:"172.20.0.0/24",
    web_ui_csrf_protection_enabled:true,
    web_ui_host_header_validation_enabled:true,
    dont_count_slow_torrents:true,
    slow_torrent_dl_rate_threshold:300,
    slow_torrent_ul_rate_threshold:30,
    slow_torrent_inactive_timer:60,
    queueing_enabled:false,
    max_active_downloads:10,
    max_active_uploads:10,
    max_active_torrents:30,
    max_ratio:2,
    max_ratio_enabled:true,
    max_ratio_act:0, # stop torrents; Servarr removes them afterward
    max_seeding_time_enabled:false,
    max_inactive_seeding_time_enabled:false,
    dl_limit:5365760, # 5240 KiB/s; API values are bytes/s
    up_limit:1024000, # 1000 KiB/s
    alt_dl_limit:0,
    alt_up_limit:0,
    scheduler_enabled:true,
    schedule_from_hour:1,
    schedule_from_min:0,
    schedule_to_hour:8,
    schedule_to_min:0,
    scheduler_days:0,
    excluded_file_names_enabled:true,
    excluded_file_names:$excluded
  }')"
  qbit_api POST app/setPreferences --data-urlencode "json=${prefs}" >/dev/null
  log "qbit: paths, categories, limits, ratio-2 stop policy, speed schedule, proxied auth bypass, WebUI validation, UPnP, and exclusions configured"
}

qbit_ensure_category() {
  local name="$1" path="$2" current
  current="$(qbit_api GET torrents/categories 2>/dev/null || echo '{}')"
  if echo "$current" | jq -e --arg n "$name" 'has($n)' >/dev/null; then
    qbit_api POST torrents/editCategory \
      --data-urlencode "category=${name}" \
      --data-urlencode "savePath=${path}" >/dev/null
    log "qbit: update category ${name} -> ${path}"
  else
    qbit_api POST torrents/createCategory \
      --data-urlencode "category=${name}" \
      --data-urlencode "savePath=${path}" >/dev/null
    log "qbit: create category ${name} -> ${path}"
  fi
}

qbit_configure() {
  qbit_wait_up || return 0
  qbit_set_prefs || { log "WARN qbit: failed to set default paths"; return 0; }
  # Empty category savePath lets qBit resolve /data/torrents/<category> in manual mode.
  qbit_ensure_category tv     "" || log "WARN qbit: failed to reconcile tv category"
  qbit_ensure_category anime  "" || log "WARN qbit: failed to reconcile anime category"
  qbit_ensure_category movies "" || log "WARN qbit: failed to reconcile movies category"
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
      local out
      if ! out="$(api "$key" POST "$url" "$want" 2>&1)"; then
        log "  WARN create ${ep} ${wname} failed: $(printf '%s' "$out" | summarize_error)"
      fi
    else
      # Some Servarr collections (notably rootfolder) support create/delete but
      # not PUT. If the desired item already exists, it is already reconciled.
      if [ "$ep" = "rootfolder" ]; then
        log "  ok ${ep}: ${wname}"
        continue
      fi

      eid="$(echo "$existing" | jq -r '.id')"
      # merge id into desired and PUT (update)
      local merged
      merged="$(echo "$want" | jq -c --argjson id "$eid" '. + {id:$id}')"
      log "  update ${ep}: ${wname}"
      local out
      if ! out="$(api "$key" PUT "${url}/${eid}" "$merged" 2>&1)"; then
        if printf '%s' "$out" | grep -q '405'; then
          log "  ok ${ep}: ${wname} already exists (API does not support update/PUT)"
        else
          log "  WARN update ${ep} ${wname} failed: $(printf '%s' "$out" | summarize_error)"
        fi
      fi
    fi
  done
}

# ---- desired-state builders -----------------------------------

qbit_json() {
  local cat="$1" cat_field="tvCategory"
  [ "$cat" = "movies" ] && cat_field="movieCategory"
  [ "$cat" = "music" ] && cat_field="musicCategory"

  jq -n --arg host "$NET_GW" --arg cat "$cat" --arg cat_field "$cat_field" \
        --arg apikey "${QBIT_API_KEY:-}" '
    { enable:true, protocol:"torrent", priority:1, name:"qBittorrent",
      removeCompletedDownloads:true, removeFailedDownloads:false,
      implementation:"QBittorrent", configContract:"QBittorrentSettings",
      fields:[ {name:"host",value:$host},{name:"port",value:8081},
               {name:"useSsl",value:false},{name:"urlBase",value:""},
               {name:"apiKey",value:$apikey},{name:$cat_field,value:$cat} ] }'
}
sab_json() {
  local cat="$1"
  jq -n --arg host "$NET_GW" --arg cat "$cat" --arg apikey "${SAB_API_KEY:-}" '
    { enable:true, protocol:"usenet", priority:1, name:"SABnzbd",
      removeCompletedDownloads:true, removeFailedDownloads:false,
      implementation:"Sabnzbd", configContract:"SabnzbdSettings",
      fields:[ {name:"host",value:$host},{name:"port",value:8080},
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
  local name="$1" url="$2" key="$3" cat="$4" root="$5" apiver="${6:-v3}"
  wait_up "$name" "$url" "$key" "$apiver" || return 0
  reconcile "$key" "$url" "downloadclient" "name" "$(clients_desired "$cat")" "$apiver"
  reconcile "$key" "$url" "rootfolder"     "path" "$(rootfolder_desired "$root")" "$apiver"
}

qbit_configure

do_arr "sonarr"       "$SONARR_URL"       "${SONARR_API_KEY:-}"       "tv"     "/data/media/tv"
do_arr "sonarr-anime" "$SONARR_ANIME_URL" "${SONARR_ANIME_API_KEY:-}" "anime"  "/data/media/anime"
do_arr "radarr"       "$RADARR_URL"       "${RADARR_API_KEY:-}"       "movies" "/data/media/movies"

# ---- Prowlarr -> applications (reconcile, v1) ------------------
prowlarr_tag_id() {
  local label="$1"
  api "${PROWLARR_API_KEY:-}" GET "${PROWLARR_URL}/api/v1/tag" 2>/dev/null |
    jq -r --arg label "$label" '.[] | select(.label==$label) | .id' | head -n1
}

prowlarr_apps_desired() {
  local tv_tag anime_tag movies_tag
  tv_tag="$(prowlarr_tag_id tv || true)"
  anime_tag="$(prowlarr_tag_id anime || true)"
  movies_tag="$(prowlarr_tag_id movies || true)"

  jq -n \
    --arg purl "$PROWLARR_URL" \
    --arg surl "$SONARR_URL"       --arg skey "${SONARR_API_KEY:-}" \
    --arg aurl "$SONARR_ANIME_URL" --arg akey "${SONARR_ANIME_API_KEY:-}" \
    --arg rurl "$RADARR_URL"       --arg rkey "${RADARR_API_KEY:-}" \
    --arg tv_tag "$tv_tag" --arg anime_tag "$anime_tag" --arg movies_tag "$movies_tag" '
    def tag_array($id): if $id == "" then [] else [($id|tonumber)] end;
    def tags_array($ids): [$ids[] | select(. != "") | tonumber];
    # Prowlarr category isolation. Standard categories include matching custom
    # categories, but anime-tagged indexers often publish anime-specific custom
    # category IDs, so keep those explicit on Sonarr-Anime too.
    def tv_categories: [5000,5010,5020,5030,5040,5045,5050,5060,5080,5090];
    def anime_categories: [5070,143862,143504,153635,107494,127941,127438,140679,125996,127720,131088,134634];
    def movie_categories: [2000,2010,2020,2030,2040,2045,2050,2060,2070,2080,2090,153635,107494,127941,127438,140679,127720,131088,134634];
    [
      {name:"Sonarr", implementation:"Sonarr", configContract:"SonarrSettings", syncLevel:"fullSync",
       tags:tag_array($tv_tag),
       fields:[
         {name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$surl},{name:"apiKey",value:$skey},
         {name:"syncCategories",value:tv_categories},{name:"animeSyncCategories",value:[]}
       ]},
      {name:"Sonarr-Anime", implementation:"Sonarr", configContract:"SonarrSettings", syncLevel:"fullSync",
       tags:tag_array($anime_tag),
       fields:[
         {name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$aurl},{name:"apiKey",value:$akey},
         {name:"syncCategories",value:[]},{name:"animeSyncCategories",value:anime_categories}
       ]},
      {name:"Radarr", implementation:"Radarr", configContract:"RadarrSettings", syncLevel:"fullSync",
       tags:tags_array([$movies_tag,$anime_tag]),
       fields:[
         {name:"prowlarrUrl",value:$purl},{name:"baseUrl",value:$rurl},{name:"apiKey",value:$rkey},
         {name:"syncCategories",value:movie_categories}
       ]}
    ]'
}

if wait_up "prowlarr" "$PROWLARR_URL" "${PROWLARR_API_KEY:-}" "v1"; then
  reconcile "${PROWLARR_API_KEY:-}" "$PROWLARR_URL" "applications" "name" \
    "$(prowlarr_apps_desired)" "v1"
  log "note: indexers are NOT managed here — add them in the Prowlarr UI (with matching tv/anime/movies tags)."
fi

# ---- Seerr (best-effort service wiring) -----------------------
# Seerr's admin/user creation is UI-wizard-bound (can't be created
# headlessly without the setup cookie). But once you've created the admin
# user in the UI and generated an API key (Settings -> General -> API Key)
# and put it in bootstrap_env as SEERR_API_KEY, we can reconcile the
# Sonarr/Radarr service entries via the API.
servarr_profile_id() {
  local key="$1" url="$2" profile="$3" profiles id
  profiles="$(api "$key" GET "${url}/api/v3/qualityprofile" 2>/dev/null || echo '[]')"
  id="$(echo "$profiles" | jq -r --arg p "$profile" '.[] | select(.name==$p) | .id' | head -n1)"
  [ -n "$id" ] && [ "$id" != "null" ] && printf '%s' "$id" || printf '1'
}

seerr_upsert_server() {
  local kind="$1" name="$2" host="$3" key="$4" profile_id="$5" profile_name="$6" dir="$7" is_default="$8" external_url="$9"
  local seerr_key="${SEERR_API_KEY:-}" base="${SEERR_URL}/api/v1" endpoint existing id payload out
  [ "$kind" = "sonarr" ] && endpoint="settings/sonarr" || endpoint="settings/radarr"
  existing="$(curl -fsS -H "X-Api-Key: $seerr_key" "${base}/${endpoint}" 2>/dev/null || echo '[]')"
  existing="$(echo "$existing" | jq -c --arg n "$name" '.[] | select(.name==$n)' | head -n1)"

  if [ "$kind" = "sonarr" ]; then
    payload="$(jq -nc --arg name "$name" --arg host "$host" --arg key "$key" \
      --argjson pid "$profile_id" --arg pname "$profile_name" --arg dir "$dir" --argjson def "$is_default" --arg external "$external_url" \
      '{name:$name,hostname:$host,port:8989,apiKey:$key,useSsl:false,baseUrl:"",
        activeProfileId:$pid,activeProfileName:$pname,activeDirectory:$dir,externalUrl:$external,is4k:false,
        isDefault:$def,enableSeasonFolders:true}')"
  else
    payload="$(jq -nc --arg name "$name" --arg host "$host" --arg key "$key" \
      --argjson pid "$profile_id" --arg pname "$profile_name" --arg dir "$dir" --argjson def "$is_default" --arg external "$external_url" \
      '{name:$name,hostname:$host,port:7878,apiKey:$key,useSsl:false,baseUrl:"",
        activeProfileId:$pid,activeProfileName:$pname,activeDirectory:$dir,externalUrl:$external,
        minimumAvailability:"released",is4k:false,isDefault:$def}')"
  fi

  if [ -n "$existing" ]; then
    id="$(echo "$existing" | jq -r '.id')"
    if out="$(curl -fsS --fail-with-body -X PUT -H "X-Api-Key: $seerr_key" -H 'Content-Type: application/json' \
      "${base}/${endpoint}/${id}" -d "$payload" 2>&1)"; then
      log "seerr: ${name} updated (${profile_name})"
    else
      log "seerr: ${name} update failed: $(printf '%s' "$out" | summarize_error)"
    fi
  else
    if out="$(curl -fsS --fail-with-body -X POST -H "X-Api-Key: $seerr_key" -H 'Content-Type: application/json' \
      "${base}/${endpoint}" -d "$payload" 2>&1)"; then
      log "seerr: ${name} linked (${profile_name})"
    else
      log "seerr: ${name} link failed: $(printf '%s' "$out" | summarize_error)"
    fi
  fi
}

seerr_wire() {
  local seerr_key="${SEERR_API_KEY:-}"
  [ -n "$seerr_key" ] || {
    log "seerr: no SEERR_API_KEY set — finish linking in the UI (one-time)"
    return 0
  }

  seerr_upsert_server sonarr "Sonarr" "172.20.0.10" "${SONARR_API_KEY:-}" \
    "$(servarr_profile_id "${SONARR_API_KEY:-}" "$SONARR_URL" "WEB-2160p")" \
    "WEB-2160p" "/data/media/tv" true "https://sonarr.${EXTERNAL_DOMAIN}"
  seerr_upsert_server sonarr "Sonarr-Anime" "172.20.0.11" "${SONARR_ANIME_API_KEY:-}" \
    "$(servarr_profile_id "${SONARR_ANIME_API_KEY:-}" "$SONARR_ANIME_URL" "[Anime] Remux-1080p")" \
    "[Anime] Remux-1080p" "/data/media/anime" false "https://sonarr-anime.${EXTERNAL_DOMAIN}"
  seerr_upsert_server radarr "Radarr" "172.20.0.12" "${RADARR_API_KEY:-}" \
    "$(servarr_profile_id "${RADARR_API_KEY:-}" "$RADARR_URL" "[SQP] SQP-1 (2160p)")" \
    "[SQP] SQP-1 (2160p)" "/data/media/movies" true "https://radarr.${EXTERNAL_DOMAIN}"
}

if curl -fsS "${SEERR_URL}/api/v1/status" >/dev/null 2>&1; then
  log "seerr up"
  seerr_wire
fi

log "bootstrap reconcile complete"
