# ================================================================
# Gluetun – ProtonVPN gateway (WireGuard + port forwarding)
#
# qBittorrent, SABnzbd and Prowlarr share this container's network
# namespace (network=container:gluetun). Their UIs are not published on
# host ports; Traefik/arr apps reach them only on the private docker net.
# Kill switch is Gluetun's default firewall (fail-closed).
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
      # to qBittorrent's API when it changes. qBit's WebUI is moved off
      # SABnzbd's default 8080 because both share this network namespace.
      VPN_PORT_FORWARDING_UP_COMMAND =
        ''/bin/sh -c 'wget -O- --retry-connrefused --post-data "json={\"listen_port\":{{PORT}}}" http://127.0.0.1:8081/api/v2/app/setPreferences 2>&1' '';

      # Containers sharing gluetun's network namespace listen on gluetun's
      # eth0 address (172.20.0.3), but gluetun's firewall blocks inbound
      # traffic on the default interface unless explicitly allowed. These are
      # needed for Traefik and the non-VPN arr apps to reach the VPN-side UIs.
      FIREWALL_INPUT_PORTS = "8080,8081,9696";
    };

    environmentFiles = lib.optional hasSecret "/run/secrets/gluetun_env";

    # Deliberately do NOT publish qBit/SAB/Prowlarr ports on the NAS host.
    # Access them through Traefik hostnames only. The FIREWALL_INPUT_PORTS
    # above opens these ports only inside gluetun's network namespace so
    # containers on media-net can connect to 172.20.0.3.
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun:/dev/net/tun"
      # Gluetun ships its own healthcheck; no override needed.
    ];
  };

  # Gluetun must be able to open /dev/net/tun; ensure module present.
  boot.kernelModules = [ "tun" ];
}
