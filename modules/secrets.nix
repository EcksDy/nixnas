# ================================================================
# NixNAS – Secrets (sops-nix + age)
#
# See docs/secrets.md. Ciphertext lives in ../secrets/*.yaml.
# The NAS decrypts at boot with its own age key:
#   /var/lib/sops-nix/nas.key
# Your PERSONAL age key (Proton Pass) is only used to EDIT secrets
# from your laptop; it never lives on the NAS.
#
# FIRST-TIME SETUP (before first rebuild that needs secrets):
#   sudo mkdir -p /var/lib/sops-nix
#   sudo age-keygen -o /var/lib/sops-nix/nas.key
#   # put the printed public key into .sops.yaml, then:
#   sops updatekeys secrets/*.yaml   # (from your laptop, with personal key)
# ================================================================
{ config, lib, ... }:
let
  # Each secret is decrypted to /run/secrets/<name>, root-only unless overridden.
  # Container env-files need to be readable by the container runtime (root reads
  # them and injects), so default perms are fine.
  secretsFile = ../secrets/arr.yaml;
  hasSecrets = builtins.pathExists secretsFile;
in
{
  sops = {
    # age key the NAS uses to decrypt at activation
    age.keyFile = "/var/lib/sops-nix/nas.key";
    age.generateKey = false;

    defaultSopsFile = lib.mkIf hasSecrets secretsFile;

    # Declare the secrets we expect. Guarded by hasSecrets so the config
    # still evaluates/builds BEFORE you've created secrets/arr.yaml.
    secrets = lib.mkIf hasSecrets {
      # Gluetun / ProtonVPN
      "gluetun_env" = { };
      # Cloudflare DNS-01 token for Traefik (rendered as env file)
      "cloudflare_env" = { };
      # Tailscale auth key (raw)
      "tailscale_authkey" = { };
      # rclone/R2 backup config (rendered as env file)
      "r2_env" = { };
      # Pinned arr API keys + download-client creds for seeding + bootstrap.
      # Readable by the media user so seeding/bootstrap (run as media) can source it.
      "bootstrap_env" = {
        owner = "media";
        group = "media";
        mode = "0440";
      };
    };
  };

  # Keep the NAS key dir present.
  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0700 root root -"
  ];
}
