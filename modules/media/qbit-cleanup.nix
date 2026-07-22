# ================================================================
# qBittorrent cleanup – remove stale metadata-only downloads
#
# Every 30 minutes, deletes torrents stuck in metadata download for >30 minutes. This is intentionally
# qBit-only: Sonarr/Radarr keep the item monitored and can grab another release via
# normal RSS/search, but we do not blocklist or trigger searches here.
# ================================================================
{ config, lib, pkgs, ... }:
let
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
in
{
  systemd.services.qbit-clean-stuck-metadata = lib.mkIf hasSecret {
    description = "Delete qBittorrent torrents stuck downloading metadata";
    after = [ "docker-qbittorrent.service" ];
    wants = [ "docker-qbittorrent.service" ];
    path = [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      User = "media";
      Group = "media";
      Environment = "QBIT_METADATA_MAX_AGE_SECONDS=1800";
    };
    script = builtins.readFile ../../scripts/qbit-clean-stuck-metadata.sh;
  };

  systemd.timers.qbit-clean-stuck-metadata = lib.mkIf hasSecret {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "30min";
      Persistent = true;
    };
  };
}
