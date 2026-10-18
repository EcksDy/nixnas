# ================================================================
# NixNAS – Shared settings / constants
#
# Central place for values referenced across modules. Change your
# domain, IP, and media uid/gid here in ONE place.
# ================================================================
{ lib, ... }:
{
  options.nixnas = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "8004228.xyz";
      description = "Base domain for reverse-proxy host rules (e.g. sonarr.\${domain}).";
    };

    lanSubnet = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "192.168.88.0/24";
      example = "192.168.1.0/24";
      description = ''
        LAN subnet to advertise via the Tailscale subnet router. Set null to
        skip subnet advertising (NAS still joins the tailnet, reachable by its
        own tailnet IP).
      '';
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Berlin";
      description = "Timezone passed to containers (TZ env).";
    };

    mediaUid = lib.mkOption {
      type = lib.types.int;
      default = 13000;
      description = "uid of the dedicated media service user.";
    };

    mediaGid = lib.mkOption {
      type = lib.types.int;
      default = 13000;
      description = "gid of the shared media group.";
    };

    appsDir = lib.mkOption {
      type = lib.types.str;
      default = "/apps/config";
      description = "Base dir for per-service container config/state (NVMe).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/data";
      description = "Media data root (HDD). Single mount into containers for hardlinks.";
    };

    repoDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = ''
        Path to the checked-out config repo on the NAS. Used by the drift
        reporter to write state-snapshots/ where `git diff` can see them.
      '';
    };

    dockerNetwork = lib.mkOption {
      type = lib.types.str;
      default = "media-net";
      description = "Docker bridge network name for the media stack.";
    };

    dockerSubnet = lib.mkOption {
      type = lib.types.str;
      default = "172.20.0.0/24";
      description = "Subnet for the media-net docker network (static IPs).";
    };

    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = ''
        Pinned container image references (repo:tag). Pin to specific tags for
        reproducible rebuilds; bump deliberately. Update tags then rebuild.
      '';
      default = {
        gluetun      = "qmcgaw/gluetun:v3.41.3";
        socketProxy  = "lscr.io/linuxserver/socket-proxy:3.4.7-r0-ls103";
        qbittorrent  = "lscr.io/linuxserver/qbittorrent:5.2.4_v2.0.15-ls480";
        sabnzbd      = "lscr.io/linuxserver/sabnzbd:5.1.3-ls277";
        sonarr       = "lscr.io/linuxserver/sonarr:4.0.20.3014-ls329";
        radarr       = "lscr.io/linuxserver/radarr:6.4.4.10685-ls321";
        lidarr       = "lscr.io/linuxserver/lidarr:3.1.0";
        prowlarr     = "lscr.io/linuxserver/prowlarr:2.6.5.5623-ls163";
        bazarr       = "lscr.io/linuxserver/bazarr:v1.6.2-ls368";
        flaresolverr = "ghcr.io/flaresolverr/flaresolverr:v3.5.2";
        jellyfin     = "lscr.io/linuxserver/jellyfin:12.2ubu2604-ls54";
        seerr        = "ghcr.io/seerr-team/seerr:v3.5.0";
        recyclarr    = "ghcr.io/recyclarr/recyclarr:8.8.0";
      };
    };
  };
}
