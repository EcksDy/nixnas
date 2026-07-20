# ================================================================
# Jellyfin (Intel Quick Sync transcode) + Jellyseerr (requests)
#
# Jellyfin uses the LinuxServer.io image with /dev/dri passthrough for QSV.
# Runs as media:media via PUID/PGID. Jellyseerr wires to Jellyfin + arr.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
  # Resolve host GIDs for QSV device access so --group-add is accurate
  # (numeric GIDs work inside the container regardless of its group db).
  renderGid = toString config.users.groups.render.gid;
  videoGid = toString config.users.groups.video.gid;
in
{
  virtualisation.oci-containers.containers = {
    jellyfin = ml.onNet {
      image = config.nixnas.images.jellyfin;
      ip = "172.20.0.4";
      environment = ml.lsioEnv // {
        JELLYFIN_PublishedServerUrl = "https://jellyfin.${cfg.domain}";
      };
      volumes = [
        "${cfg.appsDir}/jellyfin:/config"
        "${cfg.dataDir}/media:/media"
      ];
      # Intel Quick Sync: pass the render device; PUID/PGID handles the user.
      extraOptions = [
        "--device=/dev/dri:/dev/dri"
        # numeric host GIDs so the container user can access the render node
        "--group-add=${renderGid}"
        "--group-add=${videoGid}"
      ];
      labels = ml.traefikLabels { name = "jellyfin"; port = 8096; };
    };

    jellyseerr = ml.onNet {
      image = config.nixnas.images.jellyseerr;
      ip = "172.20.0.5";
      environment = {
        TZ = cfg.timezone;
        LOG_LEVEL = "info";
      };
      volumes = [
        "${cfg.appsDir}/jellyseerr:/app/config"
      ];
      labels = ml.traefikLabels { name = "jellyseerr"; port = 5055; };
    };
  };
}
