# ================================================================
# Download clients – qBittorrent (torrents) + SABnzbd (usenet)
#
# Both run INSIDE gluetun's network namespace (VPN + kill switch).
# Their web UIs are reachable via gluetun's published ports
# (8080 qbit, 8085 sab). Traefik routes to them via the gluetun IP.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
in
{
  virtualisation.oci-containers.containers = {
    qbittorrent = ml.viaGluetun {
      image = config.nixnas.images.qbittorrent;
      environment = ml.lsioEnv // {
        WEBUI_PORT = "8080";
        TORRENTING_PORT = "6881";
      };
      volumes = [
        (ml.configVol "qbittorrent")
        ml.dataVol
      ];
    };

    sabnzbd = ml.viaGluetun {
      image = config.nixnas.images.sabnzbd;
      environment = ml.lsioEnv;
      volumes = [
        (ml.configVol "sabnzbd")
        ml.dataVol
      ];
    };
  };

  # Bind downloaders to gluetun's lifecycle: when gluetun restarts (VPN
  # drop/reconnect), the shared netns is recreated -> restart dependents.
  # (Q10 resilience: systemd binding, not just ordering.)
  systemd.services."docker-qbittorrent" = {
    after = [ "docker-gluetun.service" ];
    requires = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  };
  systemd.services."docker-sabnzbd" = {
    after = [ "docker-gluetun.service" ];
    requires = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  };
}
