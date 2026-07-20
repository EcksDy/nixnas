# Backup

App **state** (not media) is backed up nightly to Cloudflare R2. Media files are not
backed up (14TB, single disk — accepted risk).

> Status: planned.

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

- `rclone` → Cloudflare R2 (S3-compatible). Credentials via sops
  (`r2_access_key_id`, `r2_secret_access_key`).
- systemd timer, nightly (~04:30).
- **SQLite-safe**: arr databases are SQLite; a live copy can corrupt. The job uses a
  consistent snapshot (brief ordered container stop, or `sqlite3 .backup` per DB) before
  pushing — never a naive copy of a live DB.
- Optional at-rest encryption via `rclone crypt` (key in sops).
- Retention: a few daily + weekly copies (rclone or R2 lifecycle rules).

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
