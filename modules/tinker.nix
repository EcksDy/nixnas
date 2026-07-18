# ================================================================
# NixNAS – Tinker tools
#
# Interactive tools for hands-on config work over SSH. NOT used by
# any automated path.
#
# proton-pass-cli:
#   Deliberate exception to the Q13 boundary (NAS never touches Proton
#   automatically). This is MANUAL only:
#     pass login          # start a session when you sit down to tinker
#     pass read / inject  # pull creds/keys as needed
#     pass logout         # END the session when done
#   sops-nix + the NAS age key remain the boot-time secret path; the
#   Proton session is never resident for automation.
#
# opencode:
#   Coding agent for editing this config interactively on the NAS.
# ================================================================
{ lib, pkgs, ... }:
{
  # proton-pass-cli is unfree (proprietary Proton). Allow ONLY it, not
  # blanket unfree, to keep the surface minimal.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "proton-pass-cli" ];

  environment.systemPackages = with pkgs; [
    proton-pass-cli   # `pass` — manual Proton Pass access; login/logout per session
    opencode          # AI coding agent for tinkering on the config
  ];
}
