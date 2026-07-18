{ config, lib, pkgs, modulesPath, ... }:
{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "ahci" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # NOTE: fileSystems are managed by disko-config.nix, not here!

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

  # Intel Quick Sync (QSV) for Jellyfin hardware transcode.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # iHD VAAPI driver (Gen9+; 8505 is Alder Lake-N)
      vpl-gpu-rt           # oneVPL runtime for QSV on recent Intel
      intel-compute-runtime
    ];
  };

  # No software RAID on DXP4800 (single NVMe + single HDD, no mdraid)
}
