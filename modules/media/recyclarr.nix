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

  # Declarative Recyclarr config. !env_var keeps keys out of the file.
  # Instance names must be globally unique across service types in Recyclarr v8.
  recyclarrYml = ''
    # Managed by NixOS (modules/media/recyclarr.nix). Do not edit in place.
    sonarr:
      sonarr-main:
        base_url: http://172.20.0.10:8989
        api_key: !env_var SONARR_API_KEY
        quality_definition:
          type: series
        # Recyclarr v8 removed the official include templates. Use guide-backed
        # quality profiles by TRaSH ID instead. This still syncs guide qualities,
        # score set, custom formats, and CF scores.
        # One "best available" profile: prefer 2160p, fall back to 1080p,
        # then 720p for older/rare shows. TRaSH's stock WEB-2160p profile is
        # 2160p-only, so we override its allowed qualities while keeping the
        # 2160p custom-format scoring.
        quality_profiles:
          - trash_id: d1498e7d189fbe6c7110ceaabb7473e6 # WEB-2160p
            name: WEB-2160p
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

      sonarr-anime:
        base_url: http://172.20.0.11:8989
        api_key: !env_var SONARR_ANIME_API_KEY
        quality_definition:
          type: anime
        quality_profiles:
          - trash_id: 20e0fc959f1f1704bed501f23bdae76f # [Anime] Remux-1080p
            name: "[Anime] Remux-1080p"

    radarr:
      radarr-main:
        base_url: http://172.20.0.12:7878
        api_key: !env_var RADARR_API_KEY
        quality_definition:
          type: movie
        # SQP-1 (2160p) is TRaSH's streaming-optimized 4K profile that
        # already includes 2160p first, then 1080p and 720p fallback.
        quality_profiles:
          - trash_id: 5128baeb2b081b72126bc8482b2a86a0 # [SQP] SQP-1 (2160p)
            name: "[SQP] SQP-1 (2160p)"
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
