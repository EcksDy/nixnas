# ================================================================
# *arr apps – Sonarr, Sonarr-anime, Radarr, Lidarr, Prowlarr, Bazarr
#
# Prowlarr runs via gluetun (indexer traffic through VPN); its UI is
# published on gluetun:9696. The rest run on media-net with static IPs
# and are routed by Traefik at <name>.<domain>.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };

  # Helper for a standard LSIO arr on media-net.
  # apiKeyEnv defaults true (servarr __AUTH__APIKEY injection); bazarr sets it
  # false because it is seeded via config.ini, not env vars, so no env file is
  # rendered for it (referencing a missing file => docker exit 125).
  arr = { name, ip, port, apiKeyEnv ? true }: ml.onNet {
    image = config.nixnas.images.${name};
    inherit ip;
    environment = ml.lsioEnv;
    environmentFiles = lib.optionals apiKeyEnv (ml.apiKeyEnvFile name);
    volumes = [
      (ml.configVol name)
      ml.dataVol
    ];
    labels = ml.traefikLabels { inherit name port; };
  };
in
{
  virtualisation.oci-containers.containers = {
    sonarr = arr { name = "sonarr"; ip = "172.20.0.10"; port = 8989; };
    radarr = arr { name = "radarr"; ip = "172.20.0.12"; port = 7878; };
    lidarr = arr { name = "lidarr"; ip = "172.20.0.13"; port = 8686; };
    bazarr = arr { name = "bazarr"; ip = "172.20.0.15"; port = 6767; apiKeyEnv = false; };

    # Second Sonarr for anime. Uses lscr sonarr image with its own config dir.
    sonarr-anime = ml.onNet {
      image = config.nixnas.images.sonarr;
      ip = "172.20.0.11";
      environment = ml.lsioEnv;
      environmentFiles = ml.apiKeyEnvFile "sonarr-anime";
      volumes = [
        (ml.configVol "sonarr-anime")
        ml.dataVol
      ];
      labels = ml.traefikLabels { name = "sonarr-anime"; port = 8989; };
    };

    # Prowlarr through the VPN (shares gluetun netns). UI published on gluetun:9696.
    prowlarr = ml.viaGluetun {
      image = config.nixnas.images.prowlarr;
      environment = ml.lsioEnv;
      environmentFiles = ml.apiKeyEnvFile "prowlarr";
      volumes = [
        (ml.configVol "prowlarr")
      ];
    };
  };

  # Prowlarr bound to gluetun lifecycle (Q10).
  systemd.services."docker-prowlarr" = {
    after = [ "docker-gluetun.service" ];
    requires = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  };

  # Prowlarr has no own media-net IP (it's in gluetun's namespace), so Traefik
  # routes to it via gluetun's IP on port 9696 using a file-provider entry.
  # Declared in modules/traefik.nix dynamic config.
}
