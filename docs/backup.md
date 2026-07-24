# Backup

App **state** (not media) is backed up nightly to Cloudflare R2. Media files are not
backed up (14TB, single disk — accepted risk).

> Status: implemented.

## What is / isn't backed up

- **IN**: `/apps/config/*` service state: arr databases (download/import history),
  Jellyfin users + watch history + "continue watching", Seerr requests, indexer
  credentials, qBittorrent/SABnzbd queues.
- **OUT**: `/data` media (too large), `/apps/docker` images (re-pullable), in-progress
  downloads, and reproducible/bulky runtime cache such as logs, Jellyfin metadata
  artwork, Seerr image cache, Sonarr/Radarr media covers, Recyclarr guide clones,
  and qBit GeoDB.

Nix reproduces the *scaffolding* (containers, wiring). It does **not** reproduce
accumulated runtime state — that's what this backup covers. Without it, a NVMe failure
brings the stack back **empty**.

## How

- `rclone` → Cloudflare R2 (S3-compatible). Credentials via sops `r2_env`
  (`RCLONE_CONFIG_R2_*` + `R2_BUCKET`).
- systemd timer, nightly (~04:30).
- **SQLite-aware**: copies app state to a temporary staging directory, then runs
  `sqlite3 .backup` for discovered `*.db`, `*.sqlite`, and `*.sqlite3` files before
  archiving. WAL/SHM files are kept during staging for safe backup, then removed
  from the archive.
- Backup logs include staged and compressed archive sizes.
- Retention: current job deletes archives older than 14 days.

## Manual run

```bash
sudo systemctl start arr-backup.service   # trigger now
journalctl -u arr-backup.service -f       # watch
```

## Restore

```bash
# Pull latest from R2 into /apps/config, then rebuild
rclone copy r2:<bucket>/apps-config /apps/config
sudo nixos-rebuild switch --flake .#nixnas
# services resume with their previous state
```
