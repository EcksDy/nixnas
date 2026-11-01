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
    # Pin upstream security fixes without updating the host package set.
    package = pkgs.stdenvNoCC.mkDerivation {
      pname = "tailscale";
      version = "1.104.4";
      src = pkgs.fetchurl {
        url = "https://dl.tailscale.com/stable/tailscale_1.104.4_amd64.tgz";
        sha256 = "624ea093d47d62cf56f17b8332d74b8decda4a1faa610ebc60a1de334b2b3dc9";
      };
      nativeBuildInputs = [ pkgs.makeWrapper ];
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 -t $out/bin tailscale tailscaled
        wrapProgram $out/bin/tailscaled \
          --prefix PATH : ${lib.makeBinPath [ pkgs.getent pkgs.iproute2 pkgs.iptables pkgs.shadow ]} \
          --suffix PATH : ${lib.makeBinPath [ pkgs.procps ]}
        substituteInPlace systemd/tailscaled.service \
          --replace-fail /usr/sbin "$out/bin"
        sed -i '/^EnvironmentFile/d' systemd/tailscaled.service
        substituteInPlace systemd/tailscale-wait-online.service \
          --replace-fail /usr/bin "$out/bin"
        install -Dm444 -t $out/lib/systemd/system systemd/*.service systemd/*.target
        runHook postInstall
      '';
      doInstallCheck = true;
      installCheckPhase = ''
        $out/bin/tailscale version | grep -Fx 1.104.4
        $out/bin/tailscaled --version | grep -Fx 1.104.4
      '';
      meta.mainProgram = "tailscale";
    };
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
