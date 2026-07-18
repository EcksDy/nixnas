# NixNAS — Ugreen DXP4800 Plus

![NixOS](https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white)
![btrfs](https://img.shields.io/badge/btrfs-zstd:1-orange)
![Docker](https://img.shields.io/badge/Docker-arr_stack-2496ED?logo=docker&logoColor=white)
![VPN](https://img.shields.io/badge/VPN-ProtonVPN-6D4AFF)
![Tailscale](https://img.shields.io/badge/Remote-Tailscale-242424?logo=tailscale&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow)

A fully declarative home NAS + media server on NixOS. Plain config files I can read,
version, and rebuild from scratch — no proprietary OS, no mystery services.

Ugreen DXP4800 Plus · 512GB NVMe (OS + apps) · 14TB WD Purple Pro (media) ·
ProtonVPN-protected *arr stack · Tailscale-only remote access.

<p align="center">
  <img src="screenshots/dashboard.png" alt="nixnas-status dashboard" width="750">
  <br>
  <em>sudo nixnas-status — live system dashboard over SSH</em>
</p>

## Documentation

| Doc | What's in it |
|---|---|
| [Base system](docs/base-system.md) | Hardware, boot, network, users, health, fan control, UGOS protection |
| [Storage](docs/storage.md) | Disk layout, TRaSH folders, hardlinks, permissions, install |
| [Secrets](docs/secrets.md) | sops-nix + age, Proton Pass key, edit/rotate workflow |
| [Media stack](docs/media-stack.md) | *arr services, Gluetun/ProtonVPN, Jellyfin QSV, declarative app config |
| [Networking & remote](docs/networking-remote.md) | Traefik, Cloudflare DNS-01 certs, Tailscale subnet router |
| [Backup](docs/backup.md) | App-state backup to Cloudflare R2 |
| [Maintenance](docs/maintenance.md) | Everyday operations, updates, troubleshooting |

Design decisions and rationale live in [`planning/`](planning/).

## Layout

```
flake.nix                    # nixpkgs 26.05 + disko + sops-nix
configuration.nix            # boot, network, users, packages, base services, Docker
disko-config.nix             # NVMe + HDD partition layout
hardware-configuration.nix   # kernel modules, CPU, firmware
modules/
  ugos-protection.nix        # UGOS SSD read-only protection
  fan-control.nix            # IT8613E out-of-tree driver + fan curve
  tinker.nix                 # opencode + proton-pass-cli (manual tinkering)
  media/                     # arr stack (oci-containers), gluetun, traefik, ...
scripts/nixnas-status        # live SSH dashboard
docs/                        # topic guides (see table above)
planning/                    # decision log
```

## Day-to-day

```bash
# Apply config changes
cd /etc/nixos && sudo nixos-rebuild switch --flake .#nixnas

# Edit a secret (personal age key from Proton Pass)
export SOPS_AGE_KEY_FILE=~/personal-age.key && sops secrets/arr.yaml

# Container status / logs
docker ps
systemctl status docker-<svc>
journalctl -u docker-<svc> -f

# Restart a service
sudo systemctl restart docker-<svc>

# Check VPN + forwarded port
docker logs gluetun | grep -i "port forward"
docker exec gluetun wget -qO- https://ipinfo.io

# Config drift report
sudo systemctl start arr-drift.service && git diff state-snapshots/

# Manual backup to R2
sudo systemctl start arr-backup.service

# Update a container image: bump tag in modules/media/<svc>.nix, then rebuild
```

## Install

First-time provisioning (destructive). Details in [storage.md](docs/storage.md) and
[base-system.md](docs/base-system.md).

```bash
# 1. Boot NixOS minimal ISO (LTS kernel). Disable BIOS WatchDog first.

# 2. Protect the UGOS SSD before anything
blockdev --setro /dev/disk/by-id/nvme-YSO128GTLCW-E3C-2_511250811096010990

# 3. Confirm HDD id matches disko-config.nix, then partition
ls /dev/disk/by-id/ | grep ata-WDC
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko ./disko-config.nix

# 4. Clone repo + install
git clone https://github.com/daskladas/nixnas.git /mnt/etc/nixos
nix --experimental-features "nix-command flakes" build \
  .#nixosConfigurations.nixnas.config.system.build.toplevel --store /mnt
nixos-install --root /mnt --system ./result --no-root-passwd

# 5. Set ADATA NVMe as BIOS boot device. Reboot, remove USB.
# 6. First login: passwd. Then provision secrets (docs/secrets.md).
```

## Known Quirks

- **WatchDog reboots** — disable the 180s BIOS watchdog (expects UGOS).
- **nixos-install crash** — use the two-step build-then-install above (flake assertion bug).
- **IT8613E fan chip** — needs the out-of-tree `it87` module; built automatically.

## License

MIT
