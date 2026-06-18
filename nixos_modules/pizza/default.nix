{
  config,
  pkgs,
  modulesPath,
  agenix,
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
    ../transmission.nix
    ../filebrowser.nix
    ../prometheus
    ../bitmagnet.nix
    ../miniflux.nix
    ../silverbullet.nix
    ../iap.nix
    ../tailscale-exit-node.nix
    ./disko.nix
    ./power.nix
    ./jellyfin.nix
    # TEMPORARY: Norte (NAS) is offline for hardware replacement; this degrades
    # Pizza so deploys succeed without the dead share. Remove when Norte is back.
    ./nas-offline.nix
    ./iptv.nix
    # Don't load headless.nix, it disables all GPU stuff but we want GPU stuff
    # for Jellyfin.
    "${modulesPath}/profiles/minimal.nix"
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
    agenix.nixosModules.default
  ];

  # Required for i915 driver to load cleanly. IIUC this because of the
  # enable_guc setting from nixos-hardware.
  hardware.enableRedistributableFirmware = true;

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
  # Note the by-partlabel path is coupled with the disko configuration.
  assertions = [
    {
      assertion = config.boot.initrd.systemd.enable;
      message = "btrfs-impermanence rollback service requires systemd stage 1 (boot.initrd.systemd.enable)";
    }
  ];
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    requires = [ "dev-disk-by\\x2dpartlabel-disk\\x2dmain\\x2droot.device" ];
    after = [ "dev-disk-by\\x2dpartlabel-disk\\x2dmain\\x2droot.device" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    # Use `script`, NOT `serviceConfig.ExecStart = pkgs.writeShellScript ...`.
    # In the systemd stage-1 initrd only the scripts generated from `script`
    # (so-called "jobScripts") get copied into the initramfs together with
    # their closure (see nixpkgs systemd/initrd.nix: jobScripts are appended to
    # `storePaths`). An ExecStart pointing at a standalone writeShellScript
    # store path is *not* pulled into the initrd, so at boot systemd can't find
    # it and the unit fails with status=203/EXEC ("Unable to locate executable
    # /nix/store/...-rollback: No such file or directory"). That's what bricked
    # the rollback after the 26.05 systemd-stage-1 switch.
    script = ''
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
  };

  # The default systemd initrd /bin ships coreutils, btrfs-progs and
  # mount/umount, but NOT findutils. The rollback script's old_roots cleanup
  # calls `find`, so add it explicitly or that loop fails at boot.
  boot.initrd.systemd.initrdBin = [ pkgs.findutils ];
  fileSystems = {
    # Defined in disko.nix, but set neededForBoot here.
    "/persistent".neededForBoot = true;
  };
  bjackman.impermanence.enable = true;

  # Group for access to the media mount from Samba.
  users.groups.nas-media = { };
  bjackman.sambaMounts.media = {
    passwordFile = ../../secrets/media-samba-password.age;
    localGroup = "nas-media";
    fileMode = "0664";
    dirMode = "0775";
    mountpoint = "/mnt/nas-media";
  };

  # Ensure media mountpoint is world-readable.
  systemd.tmpfiles.settings = {
    "10-mnt-nas-media" = {
      "/mnt/nas-media" = {
        d = {
          user = "root";
          group = "nas-media";
          mode = "0755";
        };
      };
    };
  };

  systemd.services.transmission.serviceConfig = {
    SupplementaryGroups = [ "nas-media" ];
  };
  services.transmission.settings = {
    download-dir = "/mnt/nas-media/transmission/downloads";
    incomplete-dir = "/mnt/nas-media/transmission/incomplete";
  };

  # Dynamic DNS. None of this shit is documented AFAICS, found from a
  # combination of Reddit and AI.
  age.secrets.cloudflare-dns-api-token.file = ../../secrets/cloudflare-dns-api-token.age;
  services.ddclient = {
    enable = true;
    zone = "yawn.io";
    domains = [ "home.yawn.io" ];
    protocol = "cloudflare";
    username = "token";
    passwordFile = config.age.secrets.cloudflare-dns-api-token.path;
    usev6 = "webv6, webv6=ipify-ipv6";
    usev4 = "webv4, webv4=ipify-ipv4";
  };
  # I don't think this is correct but it does make the issue go away:
  # https://discourse.nixos.org/t/seeking-advice-on-how-to-fix-ddclient-service-dependencies/74171
  systemd.services.ddclient.after = [ "nss-user-lookup.target" ];

  bjackman.iap.host = true;

  system.stateVersion = "25.11";
}
