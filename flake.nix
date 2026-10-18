{
  description = "NixNAS – NixOS NAS + Media Server Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only explicitly selected security-sensitive services use this package set.
    security-nixpkgs.url = "github:NixOS/nixpkgs/e5760179995aca4060ef511e5cb51084c8a316bd";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, security-nixpkgs, disko, sops-nix, ... }: {
    nixosConfigurations.nixnas = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs.securityPkgs = import security-nixpkgs { system = "x86_64-linux"; };
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./disko-config.nix
        ./configuration.nix
        ./hardware-configuration.nix
        ./modules/settings.nix
        ./modules/ugos-protection.nix
        ./modules/fan-control.nix
        ./modules/ugreen-leds.nix
        ./modules/secrets.nix
        ./modules/tinker.nix
        ./modules/tailscale.nix
        ./modules/traefik.nix
        ./modules/backup.nix
        ./modules/media
      ];
    };
  };
}
