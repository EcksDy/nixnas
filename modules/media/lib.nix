# Shared helpers for media oci-containers.
# Usage: let ml = import ./lib.nix { inherit config lib pkgs; }; in ...
{ config, lib, pkgs }:
let
  cfg = config.nixnas;
  net = cfg.dockerNetwork;
  m = toString cfg.mediaUid;
  g = toString cfg.mediaGid;
in
rec {
  inherit net;
  puid = m;
  pgid = g;

  # Common env for LinuxServer.io (LSIO) images
  lsioEnv = {
    PUID = m;
    PGID = g;
    TZ = cfg.timezone;
    UMASK = "002";
  };

  # A container attached to media-net with a static IP + restart policy.
  # Args: { ip, extraOptions ? [], ... } merged into the oci-container def.
  onNet = { ip, extraOptions ? [ ], ... }@args:
    (builtins.removeAttrs args [ "ip" ]) // {
      extraOptions = [
        "--network=${net}"
        "--ip=${ip}"
      ] ++ extraOptions;
      autoStart = true;
    };

  # A container sharing gluetun's network namespace (VPN sidecar).
  # No own IP; ports must be published on gluetun.
  viaGluetun = { extraOptions ? [ ], ... }@args:
    args // {
      dependsOn = (args.dependsOn or [ ]) ++ [ "gluetun" ];
      extraOptions = [ "--network=container:gluetun" ] ++ extraOptions;
      autoStart = true;
    };

  # Traefik labels for a service routed at <name>.<domain> on <port>.
  traefikLabels = { name, port }: {
    "traefik.enable" = "true";
    "traefik.docker.network" = net;
    "traefik.http.routers.${name}.rule" = "Host(`${name}.${cfg.domain}`)";
    "traefik.http.routers.${name}.entrypoints" = "websecure";
    "traefik.http.routers.${name}.tls" = "true";
    "traefik.http.routers.${name}.tls.certresolver" = "cloudflare";
    "traefik.http.services.${name}.loadbalancer.server.port" = toString port;
  };

  configVol = name: "${cfg.appsDir}/${name}:/config";
  dataVol = "${cfg.dataDir}:/data";

  # Per-service pinned API-key env file (rendered by modules/media/apikeys.nix).
  # Empty list when no secrets file exists yet (so config still evaluates/builds).
  apiKeyEnvFile = name:
    lib.optional (builtins.pathExists ../../secrets/arr.yaml)
      "/run/arr-apikeys/${name}.env";
}
