# ================================================================
# arr-bootstrap – declarative reconcile of arr wiring via APIs.
#
# Runs AUTOMATICALLY once, on first creation (fresh install has
# nothing to clobber). After that it is MANUAL ONLY — because a
# reconcile can DELETE drifted resources (config wins), we never
# auto-repeat it. A stamp file gates the first run.
#
#   Reconcile now:   sudo systemctl start arr-reconcile.service
#   Force first-run: sudo rm /apps/config/.arr-bootstrapped && sudo systemctl start arr-bootstrap.service
#   Follow logs:     journalctl -u arr-reconcile.service -f
#
# Reconciles: download clients, root folders, Prowlarr applications.
# Indexers are never touched. Needs /run/secrets/bootstrap_env.
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
  stamp = "${cfg.appsDir}/.arr-bootstrapped";
  script = pkgs.writeShellApplication {
    name = "arr-bootstrap";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = builtins.readFile ../../scripts/arr-bootstrap.sh;
  };
  # first-run wrapper: run reconcile, then drop the stamp on success.
  firstRun = pkgs.writeShellScript "arr-bootstrap-first-run" ''
    set -eu
    if [ -e "${stamp}" ]; then
      echo "arr-bootstrap: already bootstrapped (${stamp}); skipping auto-run."
      exit 0
    fi
    "${script}/bin/arr-bootstrap"
    ${pkgs.coreutils}/bin/touch "${stamp}"
    echo "arr-bootstrap: first-run complete; future runs are manual."
  '';
in
lib.mkIf hasSecret {
  systemd.services.arr-bootstrap = {
    description = "Reconcile arr stack wiring via APIs";
    # Auto-run once on (first) boot; the stamp makes it a no-op thereafter.
    # Manual full reconcile is provided by arr-reconcile.service below.
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker-sonarr.service"
      "docker-sonarr-anime.service"
      "docker-radarr.service"
      "docker-prowlarr.service"
      "docker-qbittorrent.service"
      "docker-sabnzbd.service"
      "docker-gluetun.service"
      "arr-apikeys.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      # Auto path is gated by the stamp; manual `systemctl start` uses the same
      # unit -> runs firstRun, which (if stamped) exits 0. To force a manual
      # FULL reconcile after first run, use: systemctl start arr-reconcile.
      ExecStart = "${firstRun}";
    };
  };

  # Explicit manual full-reconcile unit (ignores the stamp).
  systemd.services.arr-reconcile = {
    description = "Force a full arr reconcile now (manual)";
    after = [ "arr-apikeys.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${script}/bin/arr-bootstrap";
    };
  };
}
