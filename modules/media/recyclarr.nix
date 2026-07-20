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
        # One "best available" profile: prefer 2160p, fall back to 1080p,
        # then 720p for older/rare shows. TRaSH's stock WEB-2160p profile is
        # 2160p-only, so we override its allowed qualities while keeping the
        # 2160p custom-format scoring.
        quality_profiles:
          - name: WEB-2160p
            reset_unmatched_scores:
              enabled: true
            upgrade:
              allowed: true
              until_quality: WEB 2160p
              until_score: 10000
            min_format_score: 0
            quality_sort: top
            qualities:
              - name: WEB 2160p
                qualities:
                  - WEBDL-2160p
                  - WEBRip-2160p
              - name: WEB 1080p
                qualities:
                  - WEBDL-1080p
                  - WEBRip-1080p
              - name: Bluray-1080p
              - name: WEB 720p
                qualities:
                  - WEBDL-720p
                  - WEBRip-720p
              - name: Bluray-720p

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
          # SQP-1 (2160p) is TRaSH's streaming-optimized 4K profile that
          # already includes 2160p first, then 1080p and 720p fallback.
          - template: radarr-quality-profile-sqp-1-2160p-default
          - template: radarr-custom-formats-sqp-1-2160p
  '';

  ymlFile = pkgs.writeText "recyclarr.yml" recyclarrYml;
in
{
  virtualisation.oci-containers.containers.recyclarr = ml.onNet {
    image = config.nixnas.images.recyclarr;
    ip = "172.20.0.16";
    environment = {
      TZ = cfg.timezone;
      CRON_SCHEDULE = "@daily";
    };
    environmentFiles = lib.optional hasSecret "/run/secrets/bootstrap_env";
    extraOptions = [
      "--user=${toString cfg.mediaUid}:${toString cfg.mediaGid}"
    ];
    volumes = [
      "${cfg.appsDir}/recyclarr:/config"
      "${ymlFile}:/config/recyclarr.yml:ro"
    ];
  };
}
