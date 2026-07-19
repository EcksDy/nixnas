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
    # "server" enables ip_forward for subnet routing; "client" if no subnet.
    useRoutingFeatures = if cfg.lanSubnet != null then "server" else "client";
    authKeyFile = lib.mkIf hasSecret "/run/secrets/tailscale_authkey";
    extraUpFlags = [
      "--accept-routes"
    ] ++ lib.optional (cfg.lanSubnet != null) "--advertise-routes=${cfg.lanSubnet}";
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };
}
