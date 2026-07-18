# ================================================================
# Backup – app state (/apps/config) -> Cloudflare R2 via rclone
#
# Nightly. SQLite-safe: snapshot config to a temp dir with per-DB
# `sqlite3 .backup` for any *.db, plain copy for the rest, then push.
# Media is NOT backed up. Secret: /run/secrets/r2_env.
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../secrets/arr.yaml;
in
{
  systemd.services.arr-backup = {
    description = "Back up /apps/config to Cloudflare R2";
    path = [ pkgs.rclone pkgs.sqlite pkgs.coreutils pkgs.findutils pkgs.gnutar pkgs.zstd ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = lib.optional hasSecret "/run/secrets/r2_env";
    };
    script = ''
      set -euo pipefail
      SRC="${cfg.appsDir}"
      STAGE="$(mktemp -d)"
      trap 'rm -rf "$STAGE"' EXIT

      # SQLite-safe snapshot: for every *.db use online .backup, copy rest.
      cp -a "$SRC/." "$STAGE/"
      find "$STAGE" -type f -name '*.db' | while read -r db; do
        sqlite3 "$db" ".backup '$db.bak'" && mv -f "$db.bak" "$db" || true
      done

      TS="$(date +%Y%m%d-%H%M%S)"
      ARCHIVE="$STAGE/../apps-config-$TS.tar.zst"
      tar -C "$STAGE" -cf - . | zstd -q -o "$ARCHIVE"

      # RCLONE_CONFIG_R2_* + R2_BUCKET come from the env file.
      rclone copy "$ARCHIVE" "r2:''${R2_BUCKET}/apps-config/" --s3-no-check-bucket
      rm -f "$ARCHIVE"

      # Retention: keep last 14 archives in the bucket.
      rclone delete "r2:''${R2_BUCKET}/apps-config/" --min-age 14d || true
    '';
  };

  systemd.timers.arr-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
    };
  };
}
