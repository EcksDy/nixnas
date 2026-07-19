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
      default = "192.168.100.0/24";
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
        gluetun      = "qmcgaw/gluetun:v3.40.0";
        socketProxy  = "tecnativa/docker-socket-proxy:0.3.0";
        qbittorrent  = "lscr.io/linuxserver/qbittorrent:5.1.2";
        sabnzbd      = "lscr.io/linuxserver/sabnzbd:4.4.1";
        sonarr       = "lscr.io/linuxserver/sonarr:4.0.15";
        radarr       = "lscr.io/linuxserver/radarr:5.21.1";
        lidarr       = "lscr.io/linuxserver/lidarr:2.9.6";
        prowlarr     = "lscr.io/linuxserver/prowlarr:1.32.2";
        bazarr       = "lscr.io/linuxserver/bazarr:1.5.1";
        flaresolverr = "ghcr.io/flaresolverr/flaresolverr:v3.3.21";
        jellyfin     = "jellyfin/jellyfin:10.10.7";
        jellyseerr   = "fallenbagel/jellyseerr:2.7.3";
        recyclarr    = "ghcr.io/recyclarr/recyclarr:7.4.1";
      };
    };
  };
}
