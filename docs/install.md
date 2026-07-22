# Install & First-Time Setup

End-to-end install for the DXP4800 Plus, from the NixOS installer USB to a running
media stack. You are booted from the USB and are `root` (`sudo -i`).

Two phases:
1. **Base system** — partition, install NixOS, boot. Works WITHOUT secrets.
2. **Secrets + media stack** — add sops secrets, rebuild, the stack comes up.

The whole config is guarded by `secrets/arr.yaml`: until that encrypted file exists, the
media stack and secret-consuming modules stay inert, so the base OS installs cleanly first.

---

## Phase 1 — Base system

### 1.1 Protect the UGOS SSD (before touching disks)

```bash
blockdev --setro /dev/disk/by-id/nvme-YSO128GTLCW-E3C-2_511250811096010990
```

### 1.2 Get the config

```bash
nix-shell -p git   # installer usually has git; skip if present
git clone https://github.com/daskladas/nixnas.git /mnt/etc/nixos 2>/dev/null || true
# If /mnt isn't mounted yet, clone to /root and copy after disko:
git clone https://github.com/daskladas/nixnas.git /root/nixnas
cd /root/nixnas
```

### 1.3 Confirm disk IDs match `disko-config.nix`

```bash
ls /dev/disk/by-id/ | grep -E 'ata-WDC|ADATA'
```
- NVMe should be `nvme-ADATA_LEGEND_900_2P4929AJEANX`
- HDD should be `ata-WDC_WD141PURP-74B5YY0_7LGGD6WK`

Edit `disko-config.nix` if yours differ.

### 1.4 Partition (DESTRUCTIVE)

```bash
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko /root/nixnas/disko-config.nix
```

This creates `/`, `/boot`, `/apps` on the NVMe and `/data` (btrfs) on the HDD, and mounts
them under `/mnt`.

### 1.5 Generate the NAS age key NOW (before install)

The key must live on the installed system at `/var/lib/sops-nix/nas.key`. Create it under
`/mnt` so it persists after reboot:

```bash
mkdir -p /mnt/var/lib/sops-nix
nix --experimental-features "nix-command flakes" run nixpkgs#age -- \
  -o /mnt/var/lib/sops-nix/nas.key --generate 2>/dev/null \
  || nix-shell -p age --run 'age-keygen -o /mnt/var/lib/sops-nix/nas.key'
chmod 600 /mnt/var/lib/sops-nix/nas.key
# Print the PUBLIC key — copy this, you need it for .sops.yaml:
nix-shell -p age --run 'age-keygen -y /mnt/var/lib/sops-nix/nas.key'
```

Save that `age1...` public key. (You can also do this after first boot; doing it now means
one fewer reboot.)

### 1.6 Put the config in place + install

```bash
mkdir -p /mnt/etc/nixos
cp -r /root/nixnas/. /mnt/etc/nixos/
cd /mnt/etc/nixos

# Two-step (avoids a known nixos-install+flake assertion bug):
nix --experimental-features "nix-command flakes" build \
  .#nixosConfigurations.nixnas.config.system.build.toplevel --store /mnt
nixos-install --root /mnt --system ./result --no-root-passwd
```

### 1.7 Boot

- Set the **ADATA NVMe** as the boot device in BIOS. Disable the **WatchDog**.
- Reboot, remove USB.
- Log in as `admin` (initial password `changeme`) → `passwd` immediately.

At this point the base NAS runs (SSH, Tailscale, storage, health) but the media stack is
inert (no `secrets/arr.yaml` yet).

---

## Phase 2 — Secrets + media stack

Do the sops parts from **your laptop** (where your personal age key lives / Proton Pass),
then push to the NAS. Editing secrets needs the personal key; the NAS only needs its own
key to decrypt at boot.

### 2.1 One-time: personal age key (laptop)

```bash
age-keygen -o ~/personal-age.key          # store BOTH lines in Proton Pass
age-keygen -y ~/personal-age.key          # prints your age1... public key
```

### 2.2 Fill `.sops.yaml` with the two public keys

Edit `.sops.yaml` in the repo:
```yaml
keys:
  - &personal age1...   # from 2.1
  - &nas      age1...   # from 1.5 (NAS public key)
```

### 2.3 Create the encrypted secrets file (laptop)

```bash
export SOPS_AGE_KEY_FILE=~/personal-age.key
cp secrets/arr.yaml.example secrets/arr.yaml
sops secrets/arr.yaml     # opens decrypted; fill every REPLACE_* then save (encrypts)
```

Values you need:
- **ProtonVPN**: WireGuard private key from account.proton.me → Downloads → WireGuard.
- **Cloudflare**: DNS-edit API token (Zone:DNS:Edit + Zone:Zone:Read) for `8004228.xyz`.
- **Tailscale**: a **reusable, non-ephemeral** auth key from
  login.tailscale.com/admin/settings/keys (Reusable ON, Ephemeral OFF). The NAS auto-joins
  on first boot and advertises `192.168.100.0/24`; approve that route in the admin console
  afterwards (Machines → nixnas → Edit route settings).
- **R2**: access key id / secret / account id / bucket for backups.
- **arr API keys**: Sonarr, Sonarr-Anime, Radarr, Prowlarr, and Bazarr — generate each with `openssl rand -hex 16`.
- **qBittorrent / SABnzbd / Jellyfin / Seerr**: fill after first boot of those apps
  (see 2.6); can start empty and re-edit later.

Commit the ENCRYPTED file:
```bash
git add .sops.yaml secrets/arr.yaml && git commit -m "add secrets"
git push
```

### 2.4 Pull on the NAS + rebuild

On the NAS:
```bash
cd /etc/nixos
sudo git pull           # or scp the repo over
sudo nixos-rebuild switch --flake .#nixnas
```

Now `secrets/arr.yaml` exists → sops decrypts to `/run/secrets/*`, the media containers
start, `arr-apikeys` seeds keys, and `arr-bootstrap` runs its ONE automatic reconcile.

### 2.5 DNS + certs

- Point `*.8004228.xyz` → `192.168.100.9` in Cloudflare DNS (A record, proxy OFF/grey).
- Traefik issues the wildcard cert via DNS-01 automatically (needs the CF token).
- On LAN you reach `https://sonarr.8004228.xyz` directly; remotely via Tailscale.

### 2.6 One-time UI steps

These steps produce credentials/state that upstream apps do not currently expose as safe,
complete declarative first-run config.

1. **qBittorrent**
   - Open `https://torrent.8004228.xyz`.
   - Temporary login password is in `docker logs qbittorrent | grep -i password`.
   - Tools → Options → Web UI → API Key → Generate.
   - Put the generated `qbt_...` value in `secrets/arr.yaml` as `QBIT_API_KEY`.
2. **SABnzbd**
   - Open `https://usenet.8004228.xyz`, finish the wizard.
   - Copy Config → General → API Key into `SAB_API_KEY`.
3. **Prowlarr**
   - Open `https://prowlarr.8004228.xyz`.
   - Add indexers and credentials manually.
   - Optional Cloudflare proxy: add FlareSolverr at `http://localhost:8191` and tag only
     Cloudflare-protected indexers.
4. **Jellyfin**
   - Open `https://jellyfin.8004228.xyz`, run the setup wizard.
   - Add libraries:
     - TV Shows → `/media/tv`
     - Movies → `/media/movies`
     - Anime → `/media/anime` with content type **Shows**
     - Music → `/media/music` if you want a music library even while Lidarr is disabled
   - Dashboard → API Keys → create one → `JELLYFIN_API_KEY`.
5. **Seerr**
   - Open `https://seerr.8004228.xyz`, create the admin user.
   - Settings → General → API Key → `SEERR_API_KEY`.

After filling those, re-encrypt + push + `nixos-rebuild switch`, then run the manual jobs:
```bash
sudo docker exec recyclarr recyclarr sync      # create TRaSH profiles first
sudo systemctl start arr-reconcile.service     # wire download clients, roots, Prowlarr, Seerr
journalctl -u arr-reconcile.service -f
```

The reconcile also sets qBittorrent default/category paths:

- Default save path → `/data/torrents`
- Incomplete/temporary path enabled → `/data/torrents/incomplete`
- Categories: `tv`, `anime`, `movies` → `/data/torrents/{tv,anime,movies}`
- qBit “Use category paths in Manual Mode” enabled
- qBit queueing enabled:
  - max active downloads: 10
  - max active uploads: 5
  - max active torrents: 10
- qBit “Do not count slow torrents in these limits” enabled with thresholds:
  - download below 100 KiB/s
  - upload below 30 KiB/s
  - inactive for 60 seconds
- qBit speed schedule enabled:
  - normal download limit: 5 MiB/s
  - alternative mode from 01:00 to 09:00 every day: unlimited download
  - upload remains unlimited in both modes

In Seerr, verify server/profile selections:

- Sonarr → profile `WEB-2160p`, root `/data/media/tv`, default on.
- Sonarr-Anime → profile `[Anime] Remux-1080p`, root `/data/media/anime`, default off.
- Radarr → profile `[SQP] SQP-1 (2160p)`, root `/data/media/movies`, default on.

The `WEB-2160p`/SQP profiles are “best available” profiles: Sonarr/Radarr can grab 2160p
first, fall back to 1080p/720p when needed, and upgrade later when better releases appear.
Main Sonarr and Sonarr-Anime also prefer Season Pack releases with a moderate TRaSH score.

### 2.7 Verify

```bash
sudo nixnas-status                       # dashboard: containers, VPN, storage
docker logs gluetun | grep -i 'port forward'
docker exec gluetun wget -qO- https://ipinfo.io/ip   # should be a Proton IP
```

---

## Rotating / editing secrets later

Always from the laptop with your personal key:
```bash
export SOPS_AGE_KEY_FILE=~/personal-age.key
sops secrets/arr.yaml    # edit, save (re-encrypts), commit, push
# on NAS: git pull && sudo nixos-rebuild switch --flake .#nixnas
```

See [secrets.md](secrets.md) for the full model.
