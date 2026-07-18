# ================================================================
# NixNAS – Disko Configuration (DXP4800)
# 1x NVMe SSD 512GB (ADATA LEGEND 900) → root + /apps
# 1x HDD 14TB (WD Surveillance)         → /data (media)
#
# ⚠️ The internal UGOS SSD (nvme-YSO128GTLCW-...) is intentionally
#    NOT listed here. NEVER add it to this file!
#
# NVMe layout:
#   Part 1 – 1GB   EFI/ESP  → /boot
#   Part 2 – 64GB  ext4     → /  (NixOS root, Nix store)
#   Part 3 – rest  ext4     → /apps (Docker data, compose files, configs)
#
# HDD layout:
#   Part 1 – 100%  btrfs    → /data (media, backups, incoming)
# ================================================================
{ ... }:
{
  disko.devices = {
    disk = {
      # === NVMe (ADATA LEGEND 900 512GB) ===
      nvme = {
        device = "/dev/disk/by-id/nvme-ADATA_LEGEND_900_2P4929AJEANX";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "64G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "defaults" "noatime" ];
              };
            };
            apps = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/apps";
                mountOptions = [ "defaults" "noatime" ];
              };
            };
          };
        };
      };

      # === HDD (WD 14TB Surveillance) ===
      hdd = {
        device = "/dev/disk/by-id/ata-WDC_WD141PURP-74B5YY0_7LGGD6WK";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/data";
                mountOptions = [ "defaults" "noatime" "compress=zstd:1" "commit=3600" ];
              };
            };
          };
        };
      };
    };
  };
}
