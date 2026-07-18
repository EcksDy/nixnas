# ================================================================
# Pinned API keys via servarr ENV vars (no config.xml seeding).
#
# LSIO arr images honor the servarr env convention
#   <APP>__AUTH__APIKEY=<key>
# so the app adopts our pinned key on EVERY start (no first-run race,
# no XML templating, survives config wipes).
#
# We can't put the differently-named var directly in the shared
# bootstrap_env secret, so a oneshot renders a tiny per-service env
# file (/run/arr-apikeys/<svc>.env) BEFORE the containers start. Each
# arr container references its file via environmentFiles.
#
# Source: nixflix uses the same SONARR__AUTH__APIKEY approach.
# ================================================================
{ config, lib, pkgs, ... }:
let
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;

  # container name -> { app = servarr prefix; var = key name in bootstrap_env }
  apps = {
    sonarr       = { app = "SONARR";   var = "SONARR_API_KEY"; };
    sonarr-anime = { app = "SONARR";   var = "SONARR_ANIME_API_KEY"; };
    radarr       = { app = "RADARR";   var = "RADARR_API_KEY"; };
    lidarr       = { app = "LIDARR";   var = "LIDARR_API_KEY"; };
    prowlarr     = { app = "PROWLARR"; var = "PROWLARR_API_KEY"; };
  };

  runDir = "/run/arr-apikeys";

  renderScript = ''
    set -eu
    umask 077
    mkdir -p ${runDir}
    # shellcheck disable=SC1091
    . /run/secrets/bootstrap_env
  '' + lib.concatStringsSep "\n" (lib.mapAttrsToList (name: a: ''
    KEY="''${${a.var}:-}"
    if [ -n "$KEY" ]; then
      printf '%s__AUTH__APIKEY=%s\n' "${a.app}" "$KEY" > "${runDir}/${name}.env"
      chmod 0400 "${runDir}/${name}.env"
    fi
  '') apps);
in
lib.mkIf hasSecret {
  systemd.services.arr-apikeys = {
    description = "Render pinned servarr API-key env files";
    wantedBy = [ "multi-user.target" ];
    before = map (n: "docker-${n}.service") (lib.attrNames apps);
    requiredBy = map (n: "docker-${n}.service") (lib.attrNames apps);
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = renderScript;
  };
}
