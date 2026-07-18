# ================================================================
# Gluetun – ProtonVPN gateway (WireGuard + port forwarding)
#
# qBittorrent, SABnzbd and Prowlarr share this container's network
# namespace (network=container:gluetun), so THEIR web-UI ports are
# published HERE. Kill switch is Gluetun's default firewall (fail-closed).
#
# Secret: /run/secrets/gluetun_env (see secrets/arr.yaml.example).
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
in
{
  virtualisation.oci-containers.containers.gluetun = ml.onNet {
    image = config.nixnas.images.gluetun;
    ip = "172.20.0.3";

    environment = {
      TZ = cfg.timezone;
      # qBittorrent port-forward wiring: Gluetun pushes the forwarded port
      # to qBittorrent's API when it changes.
      VPN_PORT_FORWARDING_UP_COMMAND =
        ''/bin/sh -c 'wget -O- --retry-connrefused --post-data "json={\"listen_port\":{{PORT}}}" http://127.0.0.1:8080/api/v2/app/setPreferences 2>&1' '';
    };

    environmentFiles = lib.optional hasSecret "/run/secrets/gluetun_env";

    # Web UIs of the VPN-side containers are published here.
    ports = [
      "8080:8080"   # qBittorrent
      "8085:8085"   # SABnzbd
      "9696:9696"   # Prowlarr
    ];

    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun:/dev/net/tun"
      # Gluetun ships its own healthcheck; no override needed.
    ];
  };

  # Gluetun must be able to open /dev/net/tun; ensure module present.
  boot.kernelModules = [ "tun" ];
}
