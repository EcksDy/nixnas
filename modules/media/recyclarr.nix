# ================================================================
# Recyclarr – TRaSH quality profiles / custom formats (config -> apps)
#
# Config is rendered declaratively from Nix into
# /apps/config/recyclarr/recyclarr.yml at activation. API keys are
# NOT baked in — they use !env_var, sourced from /run/secrets/bootstrap_env
# passed to the container. Uses Recyclarr's built-in TRaSH `include`
# templates so we don't hand-copy custom-format IDs.
#
# Runs daily (CRON_SCHEDULE). Manual sync:
#   docker exec recyclarr recyclarr sync
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;

  # Declarative Recyclarr config. `include` pulls TRaSH templates shipped
  # with recyclarr (recyclarr list templates). !env_var keeps keys out of the file.
  recyclarrYml = ''
    # Managed by NixOS (modules/media/recyclarr.nix). Do not edit in place.
    sonarr:
      main:
        base_url: http://172.20.0.10:8989
        api_key: !env_var SONARR_API_KEY
        quality_definition:
          type: series
        include:
          - template: sonarr-quality-definition-series
          - template: sonarr-v4-quality-profile-web-2160p
          - template: sonarr-v4-custom-formats-web-2160p
          - template: sonarr-v4-quality-profile-web-1080p
          - template: sonarr-v4-custom-formats-web-1080p

      anime:
        base_url: http://172.20.0.11:8989
        api_key: !env_var SONARR_ANIME_API_KEY
        quality_definition:
          type: anime
        include:
          - template: sonarr-quality-definition-anime
          - template: sonarr-v4-quality-profile-anime
          - template: sonarr-v4-custom-formats-anime

    radarr:
      main:
        base_url: http://172.20.0.12:7878
        api_key: !env_var RADARR_API_KEY
        quality_definition:
          type: movie
        include:
          - template: radarr-quality-definition-movie
          - template: radarr-quality-profile-hd-bluray-web
          - template: radarr-custom-formats-hd-bluray-web
  '';

  ymlFile = pkgs.writeText "recyclarr.yml" recyclarrYml;
in
{
  # Render config at activation (overwrite — Nix is source of truth).
  systemd.tmpfiles.rules = [
    "L+ ${cfg.appsDir}/recyclarr/recyclarr.yml - - - - ${ymlFile}"
  ];

  virtualisation.oci-containers.containers.recyclarr = ml.onNet {
    image = config.nixnas.images.recyclarr;
    ip = "172.20.0.16";
    environment = {
      TZ = cfg.timezone;
      CRON_SCHEDULE = "@daily";
    };
    environmentFiles = lib.optional hasSecret "/run/secrets/bootstrap_env";
    volumes = [
      "${cfg.appsDir}/recyclarr:/config"
    ];
  };
}
