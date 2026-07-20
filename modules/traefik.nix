# ================================================================
# Traefik – native reverse proxy, TLS via Cloudflare DNS-01
#
# - Docker provider via read-only socket-proxy (172.20.0.2:2375).
# - Wildcard *.${domain} cert through Cloudflare DNS-01.
# - File provider for VPN-side services (Prowlarr, qBit, SAB) that
#   live in gluetun's namespace and are reached via gluetun's IP.
#
# Secret: /run/secrets/cloudflare_env -> CF_DNS_API_TOKEN.
# ================================================================
{ config, lib, pkgs, ... }:
let
  cfg = config.nixnas;
  gluetunIP = "172.20.0.3";
  hasSecret = builtins.pathExists ../secrets/arr.yaml;

  # VPN-side services: routed to gluetun's internal IP/ports (not NAS host-published).
  dynamicConfig = {
    http = {
      routers = {
        prowlarr = {
          rule = "Host(`prowlarr.${cfg.domain}`)";
          entrypoints = [ "websecure" ];
          service = "prowlarr";
          tls.certresolver = "cloudflare";
        };
        qbittorrent = {
          rule = "Host(`torrent.${cfg.domain}`)";
          entrypoints = [ "websecure" ];
          service = "qbittorrent";
          tls.certresolver = "cloudflare";
        };
        sabnzbd = {
          rule = "Host(`usenet.${cfg.domain}`)";
          entrypoints = [ "websecure" ];
          service = "sabnzbd";
          tls.certresolver = "cloudflare";
        };
      };
      services = {
        prowlarr.loadbalancer.servers = [{ url = "http://${gluetunIP}:9696"; }];
        qbittorrent.loadbalancer.servers = [{ url = "http://${gluetunIP}:8081"; }];
        sabnzbd.loadbalancer.servers = [{ url = "http://${gluetunIP}:8080"; }];
      };
    };
  };
in
{
  services.traefik = {
    enable = true;

    staticConfigOptions = {
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entrypoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure = {
          address = ":443";
          # Request ONE wildcard cert for the whole domain so every subdomain
          # (sonarr., torrent., usenet., ...) is covered without a per-host
          # DNS-01 challenge.
          http.tls = {
            certResolver = "cloudflare";
            domains = [{
              main = cfg.domain;
              sans = [ "*.${cfg.domain}" ];
            }];
          };
        };
      };

      providers.docker = {
        endpoint = "tcp://172.20.0.2:2375";
        exposedByDefault = false;
        network = cfg.dockerNetwork;
      };

      certificatesResolvers.cloudflare.acme = {
        email = "admin@${cfg.domain}";
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          # Check propagation against the domain's authoritative NS (Cloudflare)
          # rather than public recursors, which lag and cause
          # "did not return the expected TXT record / time limit exceeded".
          resolvers = [ "1.1.1.1:53" "8.8.8.8:53" ];
          # Give Cloudflare a moment to publish the TXT before verifying.
          delayBeforeCheck = "20";
        };
      };

      # api.dashboard could be enabled + routed later if desired.
    };

    dynamicConfigOptions = dynamicConfig;
  };

  # Cloudflare token for DNS-01 (CF_DNS_API_TOKEN) via sops env file, and
  # ordering after the media network exists.
  systemd.services.traefik = {
    after = [ "init-${cfg.dockerNetwork}.service" ];
    wants = [ "init-${cfg.dockerNetwork}.service" ];
    serviceConfig.EnvironmentFile = lib.optionals hasSecret [ "/run/secrets/cloudflare_env" ];
    # Skip lego's own DNS propagation pre-check (public recursors lag and cause
    # "did not return the expected TXT record / time limit exceeded"). Let the
    # ACME CA do the authoritative verification instead.
    environment.CF_PROPAGATION_DISABLE_CHECKS = "true";
  };
}
