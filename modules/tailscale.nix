# ================================================================
# Tailscale – subnet router (sole remote-access path)
#
# Advertises the LAN subnet so tailnet devices can reach the NAS
# (and its services via Traefik) from anywhere. No public exposure.
#
# After first boot: approve the advertised route in the Tailscale
# admin console (or configure ACL autoApprovers).
# Remote clients: `tailscale set --accept-routes`.
#
# Secret: /run/secrets/tailscale_authkey.
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../secrets/arr.yaml;
in
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server"; # enables net.ipv4.ip_forward
    authKeyFile = lib.mkIf hasSecret "/run/secrets/tailscale_authkey";
    extraUpFlags = [
      "--advertise-routes=${cfg.lanSubnet}"
      "--accept-routes"
    ];
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };
}
