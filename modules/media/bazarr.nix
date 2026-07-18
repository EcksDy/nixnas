# ================================================================
# Bazarr seeding – pinned API key + Sonarr/Radarr connections.
#
# Bazarr uses config/config.ini (not servarr env vars), so we seed a
# minimal config.ini BEFORE first start (idempotent — only if absent;
# never clobbers an existing install). It sets Bazarr's own API key and
# points Bazarr at Sonarr + Radarr using their pinned keys.
#
# Keys from /run/secrets/bootstrap_env. Runs before docker-bazarr.
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
  m = toString cfg.mediaUid;
  g = toString cfg.mediaGid;
  ini = "${cfg.appsDir}/bazarr/config/config.ini";
in
lib.mkIf hasSecret {
  systemd.services.seed-bazarr = {
    description = "Seed Bazarr config.ini (API key + Sonarr/Radarr)";
    wantedBy = [ "multi-user.target" ];
    before = [ "docker-bazarr.service" ];
    requiredBy = [ "docker-bazarr.service" ];
    after = [ "arr-apikeys.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      if [ -f "${ini}" ]; then
        echo "seed-bazarr: config.ini exists, leaving as-is"
        exit 0
      fi
      # shellcheck disable=SC1091
      . /run/secrets/bootstrap_env
      mkdir -p "$(dirname "${ini}")"
      umask 002
      {
        printf '[auth]\n'
        printf 'apikey = %s\n' "''${BAZARR_API_KEY:-}"
        printf 'type = None\n\n'
        printf '[sonarr]\n'
        printf 'ip = 172.20.0.10\nport = 8989\nbase_url = /\nssl = False\n'
        printf 'apikey = %s\n\n' "''${SONARR_API_KEY:-}"
        printf '[radarr]\n'
        printf 'ip = 172.20.0.12\nport = 7878\nbase_url = /\nssl = False\n'
        printf 'apikey = %s\n\n' "''${RADARR_API_KEY:-}"
        printf '[general]\nuse_sonarr = True\nuse_radarr = True\n'
      } > "${ini}"
      chown -R ${m}:${g} "$(dirname "${ini}")"
      echo "seed-bazarr: wrote config.ini"
    '';
  };
}
