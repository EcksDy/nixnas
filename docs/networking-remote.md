# Networking & Remote Access

Reverse proxy, TLS, and remote access. No service is exposed to the public internet;
Tailscale is the only remote path.

> Status: implemented.

## Model

```
On LAN:   device ──DNS──> 192.168.100.9 ──> Traefik ──> service
Remote:   device ──Tailscale──> 192.168.100.0/24 (subnet route) ──> Traefik ──> service
```

- Public DNS `*.yourdomain.com → 192.168.100.9` (your LAN IP). Advertising a private IP
  publicly is harmless — it's not routable from the internet.
- On the LAN, clients hit the NAS directly. No Tailscale needed at home.
- From outside, only devices on your tailnet reach `192.168.100.0/24` via the Tailscale
  subnet router. Nothing is publicly reachable.

## TLS — Cloudflare DNS-01 wildcard

- Traefik obtains `*.yourdomain.com` via the ACME **DNS-01** challenge (HTTP-01 is
  impossible with no public exposure).
- Needs a Cloudflare API token (`Zone:DNS:Edit` + `Zone:Zone:Read`) in sops
  (`cloudflare_env`).
- Tailscale's own cert features only cover `*.ts.net` names, not custom domains — not used.

## Traefik

- Native `services.traefik` with the Docker provider (`exposedByDefault = false`).
- Discovers containers through **docker-socket-proxy** (read-only) — Traefik never touches
  the raw Docker socket (privilege-escalation vector).
- Per-service routing via container labels (`traefik.http.routers.*`).
- Firewall: 80/443 open on LAN only.

## Tailscale subnet router

- `services.tailscale`, `useRoutingFeatures = "server"` (enables IP forwarding),
  `--advertise-routes=192.168.100.0/24`, `authKeyFile` from sops.
- Approve the advertised route in the Tailscale admin console (or ACL autoApprovers).
- Firewall: trust `tailscale0`, allow UDP 41641.
- Remote clients need `tailscale set --accept-routes`.

## Cloudflare Tunnel — not used

Deliberately skipped. A tunnel means public exposure, and Jellyfin streaming over the
free tier risks Cloudflare's ToS. Cloudflare is used **only** for DNS records and the
DNS-01 cert token. If non-Tailscale sharing is ever needed, revisit (tunnel
Jellyfin/Seerr behind Cloudflare Access).
