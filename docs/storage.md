# Storage

Two drives: a 512GB NVMe for OS + apps, a 14TB HDD for media. Partitioning is declarative
via disko (`disko-config.nix`).

## Layout

```
NVMe (OS + Apps) ─ ADATA LEGEND 900 512GB
├── nvme0n1p1  → /boot   (vfat, 1GB, EFI)
├── nvme0n1p2  → /       (ext4, 64GB, NixOS root + Nix store)
└── nvme0n1p3  → /apps   (ext4, ~447GB)
    ├── docker/          (Docker data-root)
    ├── config/          (per-service app state — backed up to R2)
    └── secrets scaffold (sops-decrypted secrets live in /run/secrets, not here)

HDD (Media) ─ WD Purple Pro 14TB
└── sda1       → /data   (btrfs, ~14TB, compress=zstd:1, noatime, commit=3600)
    ├── torrents/{tv,movies,music,anime}          (qBittorrent)
    ├── usenet/{incomplete,tv,movies,music,anime} (SABnzbd)
    └── media/{tv,movies,music,anime}             (Jellyfin libraries)

UGOS SSD ─ internal NVMe  (READ-ONLY, protected — see base-system.md)
```

## Why this layout

- **App state on NVMe** (`/apps/config`) — fast, and small enough to back up to R2.
- **Media + downloads on the SAME filesystem** (`/data`) — this is required for
  **hardlinks** and instant atomic-move imports (TRaSH Guides). Downloading and importing
  don't copy or double disk usage.
- **Plain directories, not btrfs subvolumes** — hardlinks do not cross subvolume
  boundaries. Keeping `torrents/`, `usenet/`, `media/` in one subvolume keeps hardlinks working.
- Follows the [TRaSH Guides](https://trash-guides.info) folder structure with English names.

## Permissions

- `/data` tree owned `media:media` (uid/gid 13000), mode `2775` (setgid so new files
  inherit the group), umask `002` (group-writable).
- Containers run as `13000:13000` (LSIO images via `PUID/PGID`, Jellyfin via `user:`).
- `admin` is in the `media` group to manage files over SSH.

## Integrity & power

- btrfs monthly scrub on `/data` (checksums catch silent corruption on the single disk).
- zstd:1 compression saves space on media.
- HDD spindown + quiet mode — see [base-system.md](base-system.md).

## No media redundancy

Single 14TB, no parity/mirror. Media is **not** backed up (too large). Accept media-loss
risk, or add a second HDD for btrfs raid1 later. App state *is* backed up — see
[backup.md](backup.md).

## Install / reprovision

```bash
# Confirm HDD device id matches disko-config.nix
ls /dev/disk/by-id/ | grep ata-WDC

# Partition (DESTRUCTIVE)
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko ./disko-config.nix
```

See the full first-time install flow in [../README.md](../README.md#install).
