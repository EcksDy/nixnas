# ================================================================
# Download clients – qBittorrent (torrents) + SABnzbd (usenet)
#
# Both run INSIDE gluetun's network namespace (VPN + kill switch).
# Their raw ports are deliberately NOT published on the NAS/LAN. Traefik
# reaches them on the internal media-net gluetun IP (8081 qBit, 8080 SAB).
# ================================================================
{ config, lib, pkgs, ... }:
let
  ml = import ./lib.nix { inherit config lib pkgs; };
  cfg = config.nixnas;
  hasSecret = builtins.pathExists ../../secrets/arr.yaml;
  sabnzbdEnv = "/run/sabnzbd/env";
  qbitInit = pkgs.writeShellScript "qbittorrent-init-config" ''
    set -euo pipefail

    conf=/config/qBittorrent/qBittorrent.conf
    [ -f "$conf" ] || exit 0

    set_conf() {
      key="$1"
      value="$2"
      tmp="$(mktemp)"
      awk -F= -v key="$key" -v value="$value" '
        BEGIN { done=0 }
        $1 == key { print key "=" value; done=1; next }
        { print }
        END { if (!done) print key "=" value }
      ' "$conf" > "$tmp"
      cat "$tmp" > "$conf"
      rm -f "$tmp"
    }

    # Ensure qBit listens on gluetun's eth0 address, not just localhost, so
    # Sonarr/Radarr/Traefik can reach it at 172.20.0.3:8081. Disable qBit's
    # Host/CSRF checks for internal Docker API clients and Traefik; auth is
    # still required for the WebUI/API.
    set_conf 'WebUI\\Address' '*'
    set_conf 'WebUI\\ServerDomains' '*'
    set_conf 'WebUI\\HostHeaderValidation' 'false'
    set_conf 'WebUI\\CSRFProtection' 'false'
    chown abc:abc "$conf"
  '';
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
        "${qbitInit}:/custom-cont-init.d/10-qbittorrent-config:ro"
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
