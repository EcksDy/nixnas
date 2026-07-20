# ================================================================
# Download clients – qBittorrent (torrents) + SABnzbd (usenet)
#
# Both run INSIDE gluetun's network namespace (VPN + kill switch).
# Their web UIs are reachable via gluetun's published ports
# (8081 qbit, 8080 sab). Traefik routes to them via the gluetun IP.
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
  sabnzbdEnv = "/run/sabnzbd/env";
  sabnzbdInit = pkgs.writeShellScript "sabnzbd-init-config" ''
    set -euo pipefail

    ini=/config/sabnzbd.ini
    mkdir -p /config
    touch "$ini"

    set_ini() {
      section="$1"
      key="$2"
      value="$3"
      tmp="$(mktemp)"
      awk -v section="$section" -v key="$key" -v value="$value" '
        BEGIN { in_section=0; section_found=0; key_done=0 }
        function emit_key() {
          if (!key_done) {
            print key " = " value
            key_done=1
          }
        }
        /^[[:space:]]*\[/ {
          if (in_section) {
            emit_key()
            in_section=0
          }
          if (tolower($0) == "[" tolower(section) "]") {
            section_found=1
            in_section=1
            print
            next
          }
        }
        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
          emit_key()
          next
        }
        { print }
        END {
          if (in_section) {
            emit_key()
          } else if (!section_found) {
            print ""
            print "[" section "]"
            print key " = " value
          }
        }
      ' "$ini" > "$tmp"
      cat "$tmp" > "$ini"
      rm -f "$tmp"
    }

    if [ -n "''${SAB_API_KEY:-}" ]; then
      set_ini misc api_key "$SAB_API_KEY"
    fi
    set_ini misc host_whitelist "usenet.${cfg.domain},192.168.100.9"
    chown abc:abc "$ini"
  '';
in
{
  virtualisation.oci-containers.containers = {
    qbittorrent = ml.viaGluetun {
      image = config.nixnas.images.qbittorrent;
      environment = ml.lsioEnv // {
        WEBUI_PORT = "8081";
        TORRENTING_PORT = "6881";
      };
      volumes = [
        (ml.configVol "qbittorrent")
        ml.dataVol
      ];
    };

    sabnzbd = ml.viaGluetun {
      image = config.nixnas.images.sabnzbd;
      environment = ml.lsioEnv;
      environmentFiles = lib.optional hasSecret sabnzbdEnv;
      volumes = [
        (ml.configVol "sabnzbd")
        ml.dataVol
        "${sabnzbdInit}:/custom-cont-init.d/10-sabnzbd-config:ro"
      ];
    };
  };

  # Bind downloaders to gluetun's lifecycle: when gluetun restarts (VPN
  # drop/reconnect), the shared netns is recreated -> restart dependents.
  # (Q10 resilience: systemd binding, not just ordering.)
  systemd.services."docker-qbittorrent" = {
    after = [ "docker-gluetun.service" ];
    requires = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  };
  systemd.services.sabnzbd-env = lib.mkIf hasSecret {
    description = "Render SABnzbd-only environment file";
    before = [ "docker-sabnzbd.service" ];
    requiredBy = [ "docker-sabnzbd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      install -d -m 0700 /run/sabnzbd
      # shellcheck disable=SC1091
      . /run/secrets/bootstrap_env
      umask 077
      printf 'SAB_API_KEY=%s\n' "''${SAB_API_KEY:-}" > ${sabnzbdEnv}
    '';
  };

  systemd.services."docker-sabnzbd" = {
    after = [ "docker-gluetun.service" "sabnzbd-env.service" ];
    requires = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  };
}
