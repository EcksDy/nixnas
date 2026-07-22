# Media Stack

The *arr automation stack: request → download (VPN-protected) → import (hardlinked) →
watch. All containers are declared as NixOS `oci-containers` (Docker backend), one
hand-written module per service under `modules/media/`.

> Status: implemented (needs secrets + first-run app wiring). Modules:
> `modules/media/{default,lib,gluetun,downloaders,arr,jellyfin,socket-proxy,recyclarr}.nix`.

## Services

| Service | Role | VPN | Access |
|---|---|---|---|
| Jellyfin | Streaming (Intel QSV transcode) | no | LAN + Tailscale |
| Seerr | Request portal | no | LAN + Tailscale |
| Sonarr | TV management | no | LAN + Tailscale |
| Sonarr-anime | Anime TV (absolute numbering, anime formats) | no | LAN + Tailscale |
| Radarr | Movies (anime movies via profile) | no | LAN + Tailscale |
| Prowlarr | Indexer aggregator + app-sync | **yes** | LAN + Tailscale |
| Bazarr | Subtitle downloading (no Whisper) | no | LAN + Tailscale |
| qBittorrent | Torrents | **yes** | LAN + Tailscale |
| SABnzbd | Usenet | **yes** | LAN + Tailscale |
| FlareSolverr | Cloudflare solver for Prowlarr | **yes** | internal |
| Gluetun | ProtonVPN gateway | — | internal |
| Recyclarr | TRaSH quality-profile sync | no | internal |
| socket-proxy | Read-only Docker API for Traefik | — | internal |

Container image tags are pinned in `modules/settings.nix` (`nixnas.images`) for
reproducible rebuilds — bump deliberately, then rebuild.

## VPN (Gluetun + ProtonVPN)

- Only **qBittorrent, SABnzbd, Prowlarr** route through the VPN via
  `--network=container:gluetun`. Streaming/management stay on the bridge.
- ProtonVPN WireGuard, with **port forwarding (natpmp)** → qBittorrent listen port
  auto-configured for good torrent connectivity.
- Kill switch: Gluetun's firewall is fail-closed — if the VPN drops, dependents have no
  internet (no leaks).
- Always-up resilience: Gluetun healthcheck self-restarts on VPN failure; dependent
  containers are bound to Gluetun's lifecycle (systemd) so they restart with it.

## Hardware transcoding

- Jellyfin gets Intel **Quick Sync** via `/dev/dri` passthrough (`hardware.graphics.enable`).
  Top priority; fully separate from everything else.
- Bazarr does subtitle **downloading** only — no Whisper/ASR, no HW accel (QSV can't
  accelerate ML transcription anyway).

## Storage & hardlinks

- Single `/data` mount into every arr container → hardlinks + instant imports.
- Folder structure and permissions: see [storage.md](storage.md).

## Declarative app config

Config is the source of truth; the UI is for volatile state (users, requests, watch
history) only. There is no "settings changed" webhook in the arr apps, so config is
**enforced**, not round-tripped.

**Pinned API keys (env-var).** Each arr's API key is fixed in sops (`bootstrap_env`).
`modules/media/apikeys.nix` renders a tiny per-service env file
(`/run/arr-apikeys/<svc>.env`) with the servarr variable `<APP>__AUTH__APIKEY` before the
containers start; each container picks it up via `environmentFiles`. LSIO images honor
this convention, so the app adopts the pinned key on every start — deterministic, no
first-run race, survives a config wipe. (Same approach nixflix uses.)

**Reconcile, not just create** (`modules/media/bootstrap.nix` + `scripts/arr-bootstrap.sh`).
Config is the source of truth. For the resources we own, the bootstrap does a full
reconcile — create missing, update changed, and **delete orphans** (present but not in
config):

- **Download clients** — qBittorrent + SABnzbd with `tv/movies/anime` categories,
  on Sonarr/Sonarr-anime/Radarr.
- **Root folders** — `/data/media/{tv,anime,movies}`.
- **Prowlarr → applications** — registers Sonarr/Sonarr-anime/Radarr so Prowlarr auto-pushes
  indexers.

**Lidarr disabled for now.** Current Lidarr 3.1 does not expose qBittorrent API-key auth
in its download-client schema; it only exposes qBit username/password fields. Since the
rest of the stack uses qBittorrent API-key auth, Lidarr is intentionally not declared.

Runs **automatically once, on first creation** (a fresh install has nothing to clobber),
gated by a stamp file `/apps/config/.arr-bootstrapped`. After that it is **manual only** —
because a reconcile can delete drifted resources, it never auto-repeats. API keys are
passed to curl via `--variable`/`--expand-header` and bodies via temp file, so no secret
ever appears on the command line.

```bash
# Force a full reconcile now (manual):
sudo systemctl start arr-reconcile.service
# Re-trigger the first-run path (e.g. after wiping config):
sudo rm /apps/config/.arr-bootstrapped && sudo systemctl start arr-bootstrap.service
journalctl -u arr-reconcile.service -f
```

> **Enforcement note:** when you run a reconcile, for those three resource types **config
> wins** — UI edits to them are reverted. Everything else is left alone. In particular,
> **indexers are never touched** (you add them in the Prowlarr UI with credentials).
> Because reconcile is manual (after first boot), your UI changes are never clobbered
> unexpectedly.

- **Recyclarr** (`modules/media/recyclarr.nix`) — TRaSH quality profiles / custom formats,
  rendered declaratively from Nix and mounted as `/config/recyclarr.yml`; keys via
  `!env_var`. Uses Recyclarr v8 guide-backed quality profiles by TRaSH ID and syncs daily.
  Manual sync: `sudo docker exec recyclarr recyclarr sync`.
- **Drift reporter** (`modules/media/drift.nix` + `scripts/arr-drift.sh`) — daily poll →
  normalized, **secret-scrubbed** JSON in `state-snapshots/`. `git diff state-snapshots/`
  surfaces any drift in the *un-enforced* areas for manual reconcile.

**Bazarr** is seeded (`modules/media/bazarr.nix`) with a pinned API key + Sonarr/Radarr
connections via `config.ini` before first start (idempotent).

**FlareSolverr** shares gluetun's namespace; add it as a proxy in Prowlarr at
`http://localhost:8191` and tag Cloudflare-protected indexers.

**Seerr**: once you create the admin user in its UI and add `SEERR_API_KEY` to
sops, the reconcile links/updates Sonarr, Sonarr-Anime, and Radarr automatically and
selects the Recyclarr quality profiles when they exist (`WEB-2160p`, `[Anime]
Remux-1080p`, `[SQP] SQP-1 (2160p)`).

Not automated (one-time UI steps): Prowlarr indexer credentials, qBittorrent WebUI API
key generation, SABnzbd first-run/API key, Jellyfin first-run wizard + libraries,
Seerr admin user + API key.

Volatile state that is *not* enforced is protected by the [backup](backup.md).

## Setup gaps and automation opportunities

Already automated:

- Stable API keys for Sonarr, Sonarr-Anime, Radarr, Prowlarr, and Bazarr.
- qBittorrent/SAB host binding and reverse-proxy safety settings via LSIO
  `/custom-cont-init.d` scripts.
- qBittorrent default save/temp paths and `tv`/`anime`/`movies` category save paths.
- Sonarr/Sonarr-Anime/Radarr download clients, root folders, and Prowlarr app links via
  `arr-reconcile.service`.
- Seerr server registration after `SEERR_API_KEY` exists.
- TRaSH/Recyclarr quality profiles and custom-format scoring via Recyclarr.
- Daily drift snapshots for review.

Could be automated next:

- Generate/check qBittorrent API-key presence in docs/status output. qBittorrent exposes
  API-key auth but upstream/LSIO do not document an env var to seed the key directly.
- More Jellyfin bootstrap via API after the first admin/API key exists: libraries,
  metadata providers, dashboard settings, and API keys.
- SABnzbd server/category configuration if/when you want usenet provider details declared
  in sops rather than entered in the UI.

Currently blocked or intentionally manual:

- Prowlarr indexer credentials: private tracker/API credentials are UI-entered and not
  declared here by design.
- Seerr first admin creation: setup is wizard/session-cookie bound before an API key exists.
- qBittorrent API-key generation: qBit documents UI generation only; no known LSIO/native
  environment variable to set it at first boot.
- Lidarr: disabled until its qBittorrent download-client schema supports qBit API-key auth
  like Sonarr/Radarr do.

## Reverse proxy

Services are routed by Traefik at `https://<service>.yourdomain.com`. Raw downloader
and indexer ports are not published on the NAS/LAN; Traefik reaches VPN-side services
through gluetun's internal media-net IP. See [networking-remote.md](networking-remote.md).
