# ================================================================
# Jellyfin (Intel Quick Sync transcode) + Seerr (requests)
#
# Jellyfin uses the LinuxServer.io image with /dev/dri passthrough for QSV.
# Runs as media:media via PUID/PGID. Seerr wires to Jellyfin + arr.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
  uidgid = "${toString cfg.mediaUid}:${toString cfg.mediaGid}";
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

    seerr = ml.onNet {
      image = config.nixnas.images.seerr;
      ip = "172.20.0.5";
      environment = {
        TZ = cfg.timezone;
        LOG_LEVEL = "info";
      };
      volumes = [
        "${cfg.appsDir}/seerr:/app/config"
      ];
      # seerr-team/seerr runs as node:node (1000:1000) by default, but our
      # appdata dirs are owned by media:media. Run it as media for writable
      # /app/config without host-side chown drift.
      extraOptions = [ "--user=${uidgid}" ];
      labels = ml.traefikLabels { name = "seerr"; port = 5055; };
    };
  };
}
