# Secrets

Secrets are encrypted in-repo with [sops-nix](https://github.com/Mic92/sops-nix) + age.
Ciphertext is committed; plaintext never touches git.

> Status: planned. Scaffolding added during the media-stack build.

## Public repo posture

This repo is public — the encrypted `secrets/*.yaml` is world-readable ciphertext. That is
the intended use of sops+age (AES-256-GCM data, X25519 recipient keys). Without a private
key it is unbreakable classically.

**Not quantum-safe.** age uses X25519, which a future quantum computer could break
("harvest-now-decrypt-later" — someone archives the public ciphertext today, decrypts it
years later). This is acceptable here because every secret is **rotatable** and none are
decades-sensitive. Mitigations:

- **Scope tightly:** the Cloudflare token is DNS-edit for one zone only; R2 creds are for
  one bucket. Rotate both periodically.
- **Rotate** anything you'd care about before the quantum timeline (`sops secrets/arr.yaml`).
- The rest (arr API keys, download-client creds, VPN key) are internal/low-value.

The bigger day-to-day risk on a public repo is **accidentally committing plaintext**. A
pre-commit hook guards against it — install once:

```bash
scripts/install-hooks
```

It blocks committing: private `*.key` files, un-encrypted `secrets/*.yaml`, and obvious
tokens (tskey-, cfat_, AWS keys, PRIVATE KEY blocks).

## Model

- **age** encryption with **OR-logic**: any one recipient's private key decrypts
  independently (age wraps a per-recipient copy of the data key). Keys don't interfere.
- Two recipients on every secret:
  - **Your personal age key** — stored in **Proton Pass**. Portable; lets you edit from
    any machine. Never lives on the NAS.
  - **Dedicated NAS age key** — `/var/lib/sops-nix/nas.key`. Machine-bound on purpose;
    lets the NAS auto-decrypt at boot. Not derived from the SSH host key (survives reinstall).
- The NAS **never logs into your Proton account.** This is deliberate — the security
  boundary is the age key, not a Proton session.

## Files

- `.sops.yaml` — creation rules listing the two recipient public keys.
- `secrets/*.yaml` — encrypted secret files (committed).
- Decrypted at activation into `/run/secrets/*` (tmpfs, root-only), fed to containers via
  `environmentFiles`.

## Inventory

- `protonvpn_wireguard_private_key`
- `cloudflare_dns_api_token` (DNS-01 wildcard cert)
- `tailscale_auth_key`
- `r2_access_key_id`, `r2_secret_access_key` (backup)
- arr API keys (pinned so enforce/backup/drift have stable creds)

## Day-to-day

```bash
# Edit / add a secret (from your laptop; key from Proton Pass)
export SOPS_AGE_KEY_FILE=~/personal-age.key
sops secrets/arr.yaml         # opens decrypted in $EDITOR; save re-encrypts
git add secrets/arr.yaml && git commit -m "update secret"

# Rotate a value: same as edit.

# Add/replace the NAS key (e.g. after reinstall)
#   add new pubkey to .sops.yaml, then:
sops updatekeys secrets/*.yaml
git commit -am "rotate NAS key"

# Recover on a new laptop: paste personal key from Proton Pass -> ~/personal-age.key
```

## First-time key generation

```bash
# Your personal key (laptop) — store BOTH lines in Proton Pass
age-keygen -o ~/personal-age.key

# NAS key (on the NAS)
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/nas.key   # public line -> .sops.yaml
```

## Proton Pass CLI (`pass`)

Proton's official [`pass-cli`](https://protonpass.github.io/pass-cli/) is installed on the
NAS (`modules/tinker.nix`) for **manual, interactive** use when you SSH in to tinker.

This is a deliberate, scoped exception to "the NAS never logs into Proton": it is
**never** used by any automated path. sops-nix + the NAS age key remain the boot-time
secret mechanism. Use `pass` only during hands-on sessions and log out afterwards:

```bash
pass login       # start a session when you sit down to work
pass read  ...   # pull a secret / cred
pass inject ...  # inject secrets into a command's env
pass logout      # END the session when done — no resident Proton session
```

On your **laptop** you can also use `pass` to pull the personal age key instead of
copy-paste. Keep it logged out when not actively editing.
