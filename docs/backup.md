# Backup

App **state** (not media) is backed up nightly to Cloudflare R2. Media files are not
backed up (14TB, single disk — accepted risk).

> Status: implemented.

## What is / isn't backed up

- **IN**: `/apps/config/*` — all per-service state: arr databases (download/import
  history), Jellyfin users + watch history + "continue watching", Seerr requests,
  indexer credentials, qBittorrent/SABnzbd queues. Tens of MB.
- **OUT**: `/data` media (too large), `/apps/docker` images (re-pullable), in-progress
  downloads.

Nix reproduces the *scaffolding* (containers, wiring). It does **not** reproduce
accumulated runtime state — that's what this backup covers. Without it, a NVMe failure
brings the stack back **empty**.

## How

- `rclone` → Cloudflare R2 (S3-compatible). Credentials via sops `r2_env`
  (`RCLONE_CONFIG_R2_*` + `R2_BUCKET`).
- systemd timer, nightly (~04:30).
- **SQLite-aware**: copies app state to a temporary staging directory, then runs
  `sqlite3 .backup` for discovered `*.db` files before archiving.
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
