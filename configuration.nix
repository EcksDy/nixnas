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
        80    # Traefik HTTP (LAN)
        443   # Traefik HTTPS (LAN)
      ];
      # NFS removed. Tailscale UDP port + trusted iface handled in modules/tailscale.nix.
    };
  };

  # ============================================================
  # Users & Groups
  # ============================================================
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" "media" ];
    initialPassword = "changeme";
    # ⚠️ Change after first login: passwd
  };

  # Dedicated non-login media service user/group (uid/gid 13000).
  # All arr containers run as this identity; owns the /data media tree.
  users.groups.media.gid = config.nixnas.mediaGid;
  users.users.media = {
    isSystemUser = true;
    uid = config.nixnas.mediaUid;
    group = "media";
    description = "Media stack service user";
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
  # oci-containers use the docker backend (Q12 decision).
  virtualisation.oci-containers.backend = "docker";

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
  #
  # /apps (NVMe): docker data-root + per-service config/state.
  # /data (HDD):  TRaSH Guides layout. torrents/usenet/media in ONE
  #               filesystem (plain dirs, NOT subvolumes) so hardlinks
  #               + instant atomic-move imports work. Owned media:media,
  #               mode 2775 (setgid) so new files inherit the group.
  # ============================================================
  systemd.tmpfiles.rules =
    let
      m = "${toString config.nixnas.mediaUid}";
      g = "${toString config.nixnas.mediaGid}";
      dataDir = config.nixnas.dataDir;
      appsBase = config.nixnas.appsDir;
      # setgid dir owned by media:media
      mediaDir = p: "d ${p} 2775 ${m} ${g} -";
    in
    [
      # --- /apps (NVMe) ---
      "d /apps/docker    0710 root  root -"
      "d ${appsBase}     0755 root  root -"
    ]
    ++ [
      # --- /data (HDD) TRaSH tree ---
      (mediaDir "${dataDir}/torrents")
      (mediaDir "${dataDir}/torrents/tv")
      (mediaDir "${dataDir}/torrents/movies")
      (mediaDir "${dataDir}/torrents/music")
      (mediaDir "${dataDir}/torrents/anime")

      (mediaDir "${dataDir}/usenet")
      (mediaDir "${dataDir}/usenet/incomplete")
      (mediaDir "${dataDir}/usenet/tv")
      (mediaDir "${dataDir}/usenet/movies")
      (mediaDir "${dataDir}/usenet/music")
      (mediaDir "${dataDir}/usenet/anime")

      (mediaDir "${dataDir}/media")
      (mediaDir "${dataDir}/media/tv")
      (mediaDir "${dataDir}/media/movies")
      (mediaDir "${dataDir}/media/music")
      (mediaDir "${dataDir}/media/anime")
    ];

  # ============================================================
  # State Version – do NOT change after install!
  # ============================================================
  system.stateVersion = "26.05";
}
