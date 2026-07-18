# Maintenance

Routine operations. Most day-to-day commands also live in the [README](../README.md).

## Validate config (no Nix on your dev machine)

Evaluate the flake in a container — catches eval/merge errors before deploying:

```bash
scripts/validate        # flake check (all modules eval + merge)
scripts/validate eval   # print toplevel derivation path
scripts/validate trace  # flake check with --show-trace
```

Requires Docker; uses the `nixos/nix` image, eval-only (no build, no host changes).

## Apply config changes

```bash
cd /etc/nixos && sudo nixos-rebuild switch --flake .#nixnas
# preview without switching:
sudo nixos-rebuild build --flake .#nixnas
# roll back:
sudo nixos-rebuild switch --rollback
```

## Containers

```bash
docker ps                              # running containers
systemctl status docker-<svc>          # one service (e.g. docker-sonarr)
journalctl -u docker-<svc> -f          # follow logs
sudo systemctl restart docker-<svc>    # restart
```

## Update container images

Images are pinned by tag in each module. To update:

1. Bump the image tag/digest in the relevant `modules/media/*.nix`.
2. `sudo nixos-rebuild switch --flake .#nixnas`.

(Avoid `latest`; pin tags so updates are deliberate and roll-back-able.)

## VPN / port forwarding

```bash
docker logs gluetun | grep -i "port forward"     # forwarded port
docker exec gluetun wget -qO- https://ipinfo.io  # confirm VPN egress IP
```

If Gluetun is unhealthy, downloaders lose internet by design (kill switch). It
self-restarts; dependents restart with it.

## Config drift report

```bash
sudo systemctl start arr-drift.service   # run the poll now
git -C /etc/nixos diff state-snapshots/  # review UI drift vs declared config
```

Fold intentional UI changes back into the declarative config, then reconcile.

## Reconcile arr wiring (manual)

The bootstrap reconcile runs **automatically once** on first creation, then only when you
invoke it. It enforces config for download clients, root folders, and Prowlarr apps
(deletes drift for those; never touches indexers).

```bash
sudo systemctl start arr-reconcile.service   # force a full reconcile now
journalctl -u arr-reconcile.service -f       # watch

# Re-run the one-time first-boot path (e.g. after wiping app config):
sudo rm /apps/config/.arr-bootstrapped
sudo systemctl start arr-bootstrap.service
```

## Backups

See [backup.md](backup.md). Trigger: `sudo systemctl start arr-backup.service`.

## Secrets

See [secrets.md](secrets.md). Edit: `sops secrets/arr.yaml` (with your personal age key).

## Health checks

```bash
sudo nixnas-status            # live dashboard
sudo smartctl -a /dev/sda     # HDD SMART
sudo btrfs scrub status /data # last scrub result
nix-collect-garbage -d        # (or rely on weekly auto-gc)
```

## Tinkering on the NAS

Interactive tools are installed via `modules/tinker.nix` (not used by any automation):

```bash
opencode          # AI coding agent — edit this config in place over SSH
pass login        # Proton Pass CLI — manual secret access; pass logout when done
```

Edit config in `/etc/nixos`, validate, then apply:

```bash
scripts/validate            # (if Docker present) or:
sudo nixos-rebuild build --flake .#nixnas
sudo nixos-rebuild switch --flake .#nixnas
```

Always `pass logout` at the end of a session — the NAS should hold no resident Proton
session.

## System upgrades (NixOS release)

1. Bump `nixpkgs` in `flake.nix` (e.g. `nixos-26.05` → next).
2. `nix flake update`.
3. `sudo nixos-rebuild switch --flake .#nixnas`.
4. Do **not** change `system.stateVersion`.
