# ================================================================
# docker-socket-proxy – read-only Docker API for Traefik
#
# Traefik never touches the raw docker socket (privilege-escalation
# vector). It talks to this proxy at tcp://172.20.0.2:2375, which
# only exposes the read endpoints needed for container discovery.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
in
{
  virtualisation.oci-containers.containers.socket-proxy = ml.onNet {
    image = config.nixnas.images.socketProxy;
    ip = "172.20.0.2";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    environment = {
      # Allow only what Traefik's docker provider needs.
      CONTAINERS = "1";
      NETWORKS = "1";
      SERVICES = "1";
      TASKS = "1";
      EVENTS = "1";
      PING = "1";
      VERSION = "1";
      # Everything else denied (default 0): POST, exec, etc.
      POST = "0";
    };
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
    ];
  };
}
