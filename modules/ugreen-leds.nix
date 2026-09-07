{ config, pkgs, ... }:

let
  source = pkgs.fetchFromGitHub {
    owner = "miskcoo";
    repo = "ugreen_leds_controller";
    tag = "v0.3";
    hash = "sha256-eSTOUHs4y6n4cacpjQAp4JIfyu40aBJEMsvuCN6RFZc=";
  };

  brightness = 64;
  networkInterface = "enp3s0";

  ledUgreen = config.boot.kernelPackages.callPackage
    ({ stdenv, kernel }:
      stdenv.mkDerivation {
        pname = "led-ugreen";
        version = "0.3";
        src = source;
        sourceRoot = "${source.name}/kmod";
        nativeBuildInputs = kernel.moduleBuildDependencies;
        makeFlags = [
          "KERNELRELEASE=${kernel.modDirVersion}"
          "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
        ];
        installPhase = ''
          install -D led-ugreen.ko \
            $out/lib/modules/${kernel.modDirVersion}/extra/led-ugreen.ko
        '';
      })
    { };
in
{
  boot.extraModulePackages = [ ledUgreen ];
  boot.kernelModules = [ "led-ugreen" "ledtrig-netdev" "ledtrig-oneshot" ];

  systemd.services.ugreen-leds = {
    description = "UGREEN front-panel LED indicators";
    wantedBy = [ "multi-user.target" ];
    requires = [ "systemd-modules-load.service" ];
    after = [ "systemd-modules-load.service" "network.target" ];
    path = [ pkgs.coreutils pkgs.smartmontools ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 5;
    };
    script = ''
      set -eu

      bus=""
      for name_path in /sys/bus/i2c/devices/i2c-*/name; do
        [ -e "$name_path" ] || continue
        case "$(<"$name_path")" in
          "SMBus I801 adapter"*)
            bus_path="''${name_path%/name}"
            bus="''${bus_path##*/}"
            break
            ;;
        esac
      done
      [ -n "$bus" ] || { echo "I801 SMBus not found" >&2; exit 1; }

      bus_number="''${bus#i2c-}"
      device="/sys/bus/i2c/devices/$bus_number-003a"
      if [ ! -d "$device" ]; then
        echo "led-ugreen 0x3a" > "/sys/bus/i2c/devices/$bus/new_device"
      elif [ "$(<"$device/name")" != "led-ugreen" ]; then
        echo "I2C address 0x3a is owned by $(<"$device/name"), not led-ugreen" >&2
        exit 1
      fi

      for attempt in {1..50}; do
        [ -d /sys/class/leds/disk4 ] && break
        sleep 0.1
      done
      for led in power netdev disk1 disk2 disk3 disk4; do
        [ -d "/sys/class/leds/$led" ] || { echo "LED $led was not detected" >&2; exit 1; }
      done

      echo none > /sys/class/leds/power/trigger
      echo "255 255 255" > /sys/class/leds/power/color
      echo ${toString brightness} > /sys/class/leds/power/brightness

      echo netdev > /sys/class/leds/netdev/trigger
      echo ${networkInterface} > /sys/class/leds/netdev/device_name
      echo 1 > /sys/class/leds/netdev/link
      echo 1 > /sys/class/leds/netdev/tx
      echo 1 > /sys/class/leds/netdev/rx
      echo 100 > /sys/class/leds/netdev/interval
      echo "255 255 255" > /sys/class/leds/netdev/color
      echo ${toString brightness} > /sys/class/leds/netdev/brightness

      for led in disk1 disk2 disk3 disk4; do
        echo none > "/sys/class/leds/$led/trigger"
        echo 0 > "/sys/class/leds/$led/brightness"
      done

      shutdown_leds() {
        for led in power netdev disk1 disk2 disk3 disk4; do
          echo none > "/sys/class/leds/$led/trigger" 2>/dev/null || true
          echo 0 > "/sys/class/leds/$led/brightness" 2>/dev/null || true
        done
      }
      trap 'shutdown_leds; exit 0' TERM INT

      declare -A mapped previous health_checked
      # ponytail: 5 Hz shell polling is enough for four bays; use the upstream
      # C++ blink-disk helper if this ever has measurable CPU cost.
      while true; do
        for slot in 1 2 3 4; do
          led="disk$slot"
          hctl="$((slot - 1)):0:0:0"
          block_dir="/sys/class/scsi_disk/$hctl/device/block"
          dev=""
          for block in "$block_dir"/*; do
            [ -e "$block" ] || continue
            dev="''${block##*/}"
            break
          done

          if [ -z "$dev" ]; then
            if [ -n "''${mapped[$led]-}" ]; then
              echo none > "/sys/class/leds/$led/trigger"
              echo 0 > "/sys/class/leds/$led/brightness"
              mapped[$led]=""
              previous[$led]=""
            fi
            continue
          fi

          if [ "''${mapped[$led]-}" != "$dev" ]; then
            echo oneshot > "/sys/class/leds/$led/trigger"
            echo 1 > "/sys/class/leds/$led/invert"
            echo 100 > "/sys/class/leds/$led/delay_on"
            echo 100 > "/sys/class/leds/$led/delay_off"
            echo "255 255 255" > "/sys/class/leds/$led/color"
            echo ${toString brightness} > "/sys/class/leds/$led/brightness"
            mapped[$led]="$dev"
            previous[$led]="$(<"/sys/class/block/$dev/stat")"
            health_checked[$led]=-300
          fi

          current="$(<"/sys/class/block/$dev/stat")"
          if [ "$current" != "''${previous[$led]}" ]; then
            echo 1 > "/sys/class/leds/$led/shot"
            previous[$led]="$current"
          fi

          last_check="''${health_checked[$led]:--300}"
          if (( SECONDS - last_check >= 300 )); then
            if smartctl -H -n standby,0 "/dev/$dev" >/dev/null 2>&1; then
              status=0
            else
              status=$?
            fi
            if (( status & ~32 )); then
              echo "255 0 0" > "/sys/class/leds/$led/color"
            else
              echo "255 255 255" > "/sys/class/leds/$led/color"
            fi
            health_checked[$led]=$SECONDS
          fi
        done
        sleep 0.2
      done
    '';
  };
}
