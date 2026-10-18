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
- **SQLite-aware**: copies app state to a temporary staging directory, then replaces
  each staged database with `sqlite3 .backup` taken directly from its live source.
  Every database backup must pass `PRAGMA quick_check`; failures abort the job.
  Database ownership and permissions are preserved for restoration.
  Copied WAL/SHM files are removed only after all database backups succeed.
- Databases are individually consistent, not one atomic snapshot of the stack.
  Before major migrations, also take a complete backup with the affected apps stopped.
- Backup logs include staged and compressed archive sizes.
- Retention: current job deletes archives older than 14 days.

## Manual run

```bash
sudo systemctl start arr-backup.service   # trigger now
journalctl -u arr-backup.service -f       # watch
```

## Restore

1. Download the selected `apps-config-*.tar.zst` archive from R2 into a private
   staging directory, using the backup job's R2 credentials. Do not download it
   directly into `/apps/config`.
2. As root, extract it into an empty directory with
   `tar --zstd -xpf <archive> -C <staging-directory>`. Service directories are at
   the archive root. Verify the extracted databases with SQLite `PRAGMA integrity_check`.
3. Stop the affected `docker-<service>.service` units. Move their current config
   directories aside, then copy the extracted service directories into `/apps/config`
   with ownership and permissions preserved.
4. Restore matching pre-upgrade image versions before restarting services. A NixOS
   generation rollback alone does not reverse application database migrations.
5. Check startup logs, settings, and application functionality before discarding the
   preserved directories.
