# ================================================================
# FlareSolverr – solves Cloudflare challenges for Prowlarr indexers.
#
# Shares gluetun's network namespace so Prowlarr can reach it at
# http://localhost:8191 (both are in the same netns). No web UI to
# expose. Bound to gluetun's lifecycle like the other VPN-side svcs.
#
# In Prowlarr: Settings -> Indexers -> add a FlareSolverr proxy with
# host http://localhost:8191 and tag it on indexers that need it.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
in
{
  virtualisation.oci-containers.containers.flaresolverr = ml.viaGluetun {
    image = cfg.images.flaresolverr;
    environment = {
      TZ = cfg.timezone;
      LOG_LEVEL = "info";
    };
  };

  # Prowlarr + FlareSolverr share gluetun's netns, so Prowlarr reaches it at
  # localhost:8191 — no port publishing needed. Bind to gluetun's lifecycle.
  systemd.services."docker-flaresolverr" = {
    after = [ "docker-gluetun.service" ];
    requires = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  };
}
