# ================================================================
# NixNAS – Media stack aggregator
#
# Imports all media modules and sets up shared infrastructure:
#   - the media-net docker network (static IPs)
#   - per-service config dirs on /apps/config (owned media:media)
#
# Static IP plan (172.20.0.0/24):
#   .2 socket-proxy   .3 gluetun      .4 jellyfin    .5 seerr
#   .10 sonarr        .11 sonarr-anime .12 radarr    .13 unused (lidarr disabled)
#   .14 prowlarr(vpn) .15 bazarr       .16 recyclarr
#   qbittorrent/sabnzbd share gluetun's namespace (no own IP)
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  net = cfg.dockerNetwork;
  subnet = cfg.dockerSubnet;
in
{
  imports = [
    ./gluetun.nix
    ./downloaders.nix
    ./arr.nix
    ./flaresolverr.nix
    ./jellyfin.nix
    ./recyclarr.nix
    ./socket-proxy.nix
    ./apikeys.nix
    ./bazarr.nix
    ./bootstrap.nix
    ./qbit-cleanup.nix
    ./drift.nix
  ];

  # --- Docker network for the whole stack (idempotent) ---
  systemd.services."init-${net}" = {
    description = "Create docker network ${net}";
    after = [ "docker.service" "docker.socket" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.docker}/bin/docker network inspect ${net} >/dev/null 2>&1 || \
        ${pkgs.docker}/bin/docker network create \
          --driver bridge \
          --subnet ${subnet} \
          ${net}
    '';
  };

  # --- Per-service config/state dirs on NVMe (owned media:media) ---
  systemd.tmpfiles.rules =
    let
      m = toString cfg.mediaUid;
      g = toString cfg.mediaGid;
      d = name: "d ${cfg.appsDir}/${name} 0775 ${m} ${g} -";
    in
    map d [
      "gluetun"
      "qbittorrent"
      "sabnzbd"
      "sonarr"
      "sonarr-anime"
      "radarr"
      "prowlarr"
      "bazarr"
      "jellyfin"
      "seerr"
      "recyclarr"
    ];
}
