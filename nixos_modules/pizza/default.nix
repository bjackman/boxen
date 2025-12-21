{
  config,
  pkgs,
  modulesPath,
  nixos-hardware,
  lib,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../server.nix
    ../impermanence.nix
    ./disko.nix
    ./power.nix
    ./jellyfin.nix
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking.hostName = "pizza";

  time.timeZone = "Europe/Zurich";

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  networking.useDHCP = false;
  networking.networkmanager.enable = false;
  systemd.network = {
    enable = true;
    networks."10-eth-default" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
    };
  };
  services.resolved.enable = true;

  # BTRFS-based impermanence.  Adapted from the example at
  # https://github.com/nix-community/impermanence. IIUC this is mounting the
  # root of the BTRFS subvolume hierarchy. Then it moves the /root subvolume
  # under /old_roots. According to AI, even though this is a plain old mv
  # operation, it actually rearranges the subvolumes. Then we create a new /root
  # subvolume and delete old ones (older than 30d). This all happens before the
  # rootfs gets mounted.
  # Note the by-partlabel path is coupled with the disko configuration.n
  boot.initrd.postResumeCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount /dev/disk/by-partlabel/disk-main-root /btrfs_tmp
    if [[ -e /btrfs_tmp/root ]]; then
        mkdir -p /btrfs_tmp/old_roots
        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
    fi

    delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
    }

    for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
        delete_subvolume_recursively "$i"
    done

    btrfs subvolume create /btrfs_tmp/root
    umount /btrfs_tmp
  '';
  fileSystems = {
    # Defined in disko.nix, but set neededForBoot here.
    "/persistent".neededForBoot = true;
  };
  bjackman.impermanence.enable = true;

  system.stateVersion = "25.11";
}
