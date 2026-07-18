{ config, pkgs, lib, ... }:
{
  # ============================================================
  # Boot
  # ============================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;


  # ============================================================
  # Nix Settings
  # ============================================================
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # ============================================================
  # Locale
  # ============================================================
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de";

  # ============================================================
  # Network
  # ============================================================
  networking = {
    hostName = "nixnas";
    useDHCP = false;
    interfaces.enp3s0 = {
      ipv4.addresses = [{
        address = "192.168.60.3";
        prefixLength = 24;
      }];
    };
    defaultGateway = "192.168.60.1";
    nameservers = [ "192.168.60.2" "192.168.60.1" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22    # SSH
        2049  # NFS
      ];
      allowedUDPPorts = [
        2049  # NFS
      ];
    };
  };

  # ============================================================
  # User
  # ============================================================
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    initialPassword = "changeme";
    # ⚠️ Change after first login: passwd
  };

  # ============================================================
  # SSH
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # ============================================================
  # Terminal Environment
  # ============================================================
  environment.variables.TERM = "xterm-256color";

  # ============================================================
  # HDD Spindown & Acoustic Management
  # ============================================================
  systemd.services.hdd-power-management = {
    description = "Set HDD spindown timer and acoustic management";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Spindown after 20 minutes idle (value 240 = 20min * 5s units)
      ${pkgs.hdparm}/bin/hdparm -S 240 /dev/sda || true
      # Acoustic Management: 128 = quiet mode
      ${pkgs.hdparm}/bin/hdparm -M 128 /dev/sda || true
    '';
  };

  # ============================================================
  # Fail2Ban – SSH brute-force protection
  # ============================================================
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "48h";
    };
    jails.sshd = {
      settings = {
        enabled = true;
        port = "ssh";
        filter = "sshd";
        maxretry = 5;
      };
    };
  };

  # ============================================================
  # Packages
  # ============================================================
  environment.systemPackages = with pkgs; [
    # Editors
    nano
    vim

    # System info & monitoring
    htop
    btop
    iotop
    fastfetch
    lsof
    pciutils       # lspci
    usbutils       # lsusb
    dmidecode      # hardware info
    lm_sensors

    # Disk tools
    smartmontools  # smartctl
    hdparm
    btrfs-progs
    parted
    gptfdisk       # gdisk, sgdisk
    nvme-cli       # nvme smart-log, etc.
    ncdu           # disk usage

    # Network tools
    ethtool        # NIC info
    iperf3         # bandwidth test
    dnsutils       # dig, nslookup

    # General utilities
    git
    tmux
    rsync
    wget
    curl
    tree
    file
    unzip
    jq
    bc
    efibootmgr

    # Docker management
    docker-compose

    # Dashboard tool
    (writeShellScriptBin "nixnas-status" (builtins.readFile ./scripts/nixnas-status))
  ];

  # ============================================================
  # Docker
  # ============================================================
  virtualisation.docker = {
    enable = true;
    # Store Docker data on NVMe /apps partition
    daemon.settings = {
      data-root = "/apps/docker";
    };
  };

  # ============================================================
  # SMART Monitoring
  # ============================================================
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.mail.enable = false;
    # Short self-test daily 04:00, long self-test Sunday 02:00
    # Temperature warning at 45°C, critical at 55°C
    defaults.monitored = "-a -o on -S on -n standby,q -s (S/../.././04|L/../../7/02) -W 4,45,55";
  };

  # ============================================================
  # btrfs Scrub – monthly data integrity check
  # ============================================================
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/data" ];
  };

  # ============================================================
  # Directory Structure
  # ============================================================
  systemd.tmpfiles.rules = [
    # --- /apps (NVMe) – Docker, compose files, app configs ---
    "d /apps/docker          0710 root   root   -"
    "d /apps/compose         0755 admin  users  -"
    "d /apps/config          0755 admin  users  -"

    # --- /data (HDD) – media files only ---
    "d /data/backup          0755 admin  users  -"
    "d /data/backup/pve-lab  0755 admin  users  -"
    "d /data/backup/pve-proxway 0755 admin users -"
    "d /data/media           0755 admin  users  -"
    "d /data/media/Anime     0755 admin  users  -"
    "d /data/media/Filme     0755 admin  users  -"
    "d /data/media/Serien    0755 admin  users  -"
    "d /data/media/Musik     0755 admin  users  -"
    "d /data/incoming        0755 admin  users  -"
    "d /data/incoming/Anime  0755 admin  users  -"
    "d /data/incoming/Filme  0755 admin  users  -"
    "d /data/incoming/Serien 0755 admin  users  -"
    "d /data/incoming/Musik  0755 admin  users  -"
  ];

  # ============================================================
  # State Version – do NOT change after install!
  # ============================================================
  system.stateVersion = "25.11";
}
