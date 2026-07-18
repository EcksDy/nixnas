{
  description = "NixNAS – NixOS NAS + Media Server Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, sops-nix, ... }: {
    nixosConfigurations.nixnas = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./disko-config.nix
        ./configuration.nix
        ./hardware-configuration.nix
        ./modules/settings.nix
        ./modules/ugos-protection.nix
        ./modules/fan-control.nix
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
