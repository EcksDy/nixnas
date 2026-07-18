# Base System

The foundational NixOS host: hardware, boot, network, users, health, fan control,
and UGOS protection. Everything here is the plain-NAS layer beneath the media stack.

## Hardware

| | |
|-|-|
| Device | Ugreen DXP4800 Plus (4-Bay) |
| CPU | Intel Pentium Gold 8505 (5C/6T, Intel Quick Sync) |
| RAM | 8 GB DDR5 |
| OS + Apps | ADATA LEGEND 900 512GB NVMe |
| Data | WD Purple Pro 14TB (WD141PURP) |
| Network | 2.5GbE (+ unused 10GbE) |

## Boot

- systemd-boot, EFI. BIOS boots directly from the ADATA NVMe ESP (`/boot`).
- Set the ADATA NVMe as boot device in BIOS. No bootloader lives on the UGOS SSD.
- Disable the BIOS **WatchDog** — it reboots after 180s expecting UGOS to respond.

## Network

- Static `192.168.60.3/24`, gateway `192.168.60.1`, DNS `192.168.60.2` / `.1`.
- Interface `enp3s0`.
- Firewall: SSH (22) only on LAN. (NFS removed — see below. Reverse-proxy 80/443 and
  Tailscale added by the media/networking layer.)

## Users

- `admin` — normal user, groups `wheel networkmanager docker media`. Initial password
  `changeme`, **change on first login** (`passwd`).
- `media` — non-login service user/group, uid/gid **13000**. Owns `/data` media tree and
  runs the container workloads. See [storage.md](storage.md).

## SSH

- Password auth enabled, root login disabled.
- Fail2Ban on SSH: 5 attempts → 1h ban, escalating to 48h.

## Health Monitoring

- **smartd**: short self-test daily 04:00, long test Sunday 02:00. Temp warn 45°C / crit 55°C.
- **btrfs autoScrub**: monthly integrity check on `/data`.
- **HDD power management**: spindown after 20 min idle (`hdparm -S 240`) + quiet acoustic
  mode (`-M 128`) on `/dev/sda`. Usage pattern (batched nightly writes, occasional reads)
  suits spindown; expect a ~5-10s wake on first cold access.

## Fan Control

The DXP4800 Plus uses an ITE **IT8613E** Super-I/O chip the mainline kernel doesn't
support. Config builds the out-of-tree `it87` module from source
(`frankcrawford/it87`), loads it with `force_id=0x8613 ignore_resource_conflict=1`, and
sets `acpi_enforce_resources=lax`. A systemd service initialises fan channels on boot:

- `pwm2` (HDD cage) → auto
- `pwm3` (system/rear) → manual constant (`50`) to stop idle fan cycling
- `pwm4/pwm5` → auto (no fans)

## UGOS Protection

The internal UGOS SSD (Ugreen's OS) is kept intact for warranty. Four layers ensure it's
never written:

1. Excluded from `disko-config.nix` (never partitioned).
2. udev rule sets it read-only by serial on detection.
3. systemd service re-applies read-only every boot.
4. No mount entries anywhere.

UGOS SSD serial: `YSO128GTLCW-E3C-2_511250811096010990`. Restoring UGOS = BIOS boot
order change. See `modules/ugos-protection.nix`.

## NFS — removed

The original config exported `/data/backup` (Proxmox), `/data/media` (external Jellyfin),
and `/data/incoming` (staging). None apply here: Jellyfin runs locally in a container and
there is no Proxmox. NFS and its firewall ports (2049) are removed.

## Dashboard

`sudo nixnas-status` — a ~350-line bash dashboard (bundled via `writeShellScriptBin`,
no install). Shows system stats, network, storage usage, SMART status/temps, and
services. Refreshes every 5s via cursor repositioning.
