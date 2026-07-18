# ================================================================
# arr-drift – daily config drift snapshot (Q3 reporter).
#
# Polls app APIs, writes normalized + secret-scrubbed JSON to
# /etc/nixos/state-snapshots. `git diff` surfaces UI drift from the
# enforced/declared config; fold intentional changes back by hand.
#
# Manual run:  sudo systemctl start arr-drift.service
#              git -C /etc/nixos diff state-snapshots/
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
  snapDir = "${cfg.repoDir}/state-snapshots";
  script = pkgs.writeShellApplication {
    name = "arr-drift";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = builtins.readFile ../../scripts/arr-drift.sh;
  };
in
lib.mkIf hasSecret {
  systemd.services.arr-drift = {
    description = "Snapshot arr config via API for git-diff review";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${script}/bin/arr-drift";
      # root: needs /run/secrets + write to the repo's state-snapshots dir
      Environment = "OUT=${snapDir}";
    };
  };

  systemd.timers.arr-drift = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${snapDir} 0755 root root -"
  ];
}
