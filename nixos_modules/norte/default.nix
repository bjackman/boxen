{
  pkgs,
  config,
  modulesPath,
  nixos-raspberrypi,
  homelab,
  ...
}:
{
  # This was figured out with great pain and anguish, not by reading docs.
  imports = [
    nixos-raspberrypi.nixosModules.sd-image
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    ../brendan.nix
    ../server.nix
    ../common.nix
    ../users.nix
    ../node-exporter.nix
    ../restic-exporter.nix
    ../iap.nix
    # Need to run {Rad,Son}arr locally so they can do hardlinks
    ../arr.nix
    ./restic-exporter.nix
    ./samba-server.nix
    ./sftp-server.nix
    ./zfs.nix
    # Warning: she doesn't have vewwy much WAM uwu
    # Check https://perses.home.yawn.io/projects/homelab/dashboards/node-exporter-nodes?var-instance=norte
  ];

  boot.loader.raspberry-pi.bootloader = "kernel";

  networking.hostName = "norte";

  zramSwap.enable = true;

  # Build getting stuck at "building man-cache", try disabling that...?
  documentation.man.generateCaches = false;

  hardware.raspberry-pi.config = {
    # As per
    # https://github.com/bjackman/nas/blob/486592769ca3fa7e186438520e745c485b116ebd/README.md?plain=1#L32
    # (via https://docs.radxa.com/en/accessories/storage/penta-sata-hat/penta-for-rpi5#enable-pcie),
    # need to set dtparam=pciex1 in the config.txt. There's an example of the
    # nixos-raspberrypi Nix magic here:
    # https://github.com/nvmd/nixos-raspberrypi/blob/develop/modules/configtxt.nix
    # All of them seem to have "values" while this param doesn't seem to have
    # that. Luckily I guessed this format and it did correctly update the
    # /boot/firmware/config.txt .
    all.base-dt-params = {
      pciex1.enable = true;
    };

    # Opus 4.8:
    #
    # Workaround for the Penta SATA HAT's JMicron JMB585 SATA controller failing
    # to initialise on newer Raspberry Pi kernels.
    #
    # How this was diagnosed (2026-06-07):
    #
    # A deploy bumped the (nixos-raspberrypi-pinned) kernel from
    # linux_rpi-bcm2712 6.12.47-stable to 6.12.87-unstable. After rebooting,
    # norte fell off the network entirely. Pulling the SD card and reading
    # /var/log/journal from the failed boot showed it had dropped to
    # emergency.target:
    #
    #     zfs-import-nas-start: Pool nas in state MISSING, waiting   (x~14)
    #     cannot import 'nas': no such pool available
    #     zfs-import-nas.service: Failed with result 'exit-code'.
    #     Dependency failed for /mnt/nas  ->  Local File Systems  ->  emergency
    #
    # "no such pool available" means the *disks themselves* were absent, not a
    # ZFS force-import / hostid problem (so boot.zfs.forceImportRoot is
    # irrelevant here). Grepping the kernel log for the controller pinned it
    # down. The JMB585 (PCI id 197b:0585) probed but the AHCI driver bailed:
    #
    #     ahci 0001:01:00.0: controller can't do 64bit DMA, forcing 32bit
    #     ahci 0001:01:00.0: failed to start port 0 (errno=-12)   # -12 = ENOMEM
    #     ahci 0001:01:00.0: probe with driver ahci failed with error -12
    #
    # Comparing against the last *good* boot (6.12.47) of the very same hardware,
    # the controller there came up cleanly with 64-bit DMA and enumerated the
    # disks:
    #
    #     ahci 0001:01:00.0: flags: 64bit ncq sntf stag pm led clo pmp ...
    #     ata1: SATA link up 6.0 Gbps ... ata1.00: ATA-11: WDC WDS100T1R0A ...
    #
    # (The "BAR n [io ...] failed to assign; no space" lines appear identically
    # in BOTH boots, so they're a harmless red herring - AHCI uses the MEM BAR.)
    #
    # Root cause: newer kernels apply a quirk that marks the JMB58x as unable to
    # do 64-bit DMA and force it to 32-bit. But the Pi 5's PCIe has no
    # 32-bit-addressable inbound DMA window configured by default, so the
    # driver's 32-bit DMA allocation fails with ENOMEM and the port never
    # starts. The fix is the stock `pcie-32bit-dma-pi5` overlay, which sets up a
    # 32-bit DMA window (bouncing buffers via swiotlb). Per
    # /boot/firmware/overlays/README:
    #   "pcie-32bit-dma-pi5: Force PCIe config to support 32bit DMA addresses at
    #    the expense of having to bounce buffers (on the Pi 5)."
    #
    # Recovery while this wasn't in place: the firmware boots from
    # `os_prefix=nixos/default/` in config.txt, and each generation is kept in
    # /boot/firmware/nixos/<gen>-default/. Editing os_prefix to point at the
    # last-good gen (e.g. nixos/129-default/) rolls back without a working OS.
    all.dt-overlays = {
      pcie-32bit-dma-pi5 = {
        enable = true;
        params = { };
      };
    };
  };

  # The ZFS pool attached to this system was created before I installed NixOS,
  # using Ubuntu.
  # Following the suggestion of AI, I set mountpoint=legacy for each of the
  # datasets to stop zfs tools from auto-mounting them.
  boot.zfs.extraPools = [ "nas" ];
  fileSystems."/mnt/nas" = {
    device = "nas";
    fsType = "zfs";
    options = [ "nofail" ];
  };
  # /mnt/nas directly mounts the root dataset of the pool. In order to avoid
  # needing to snapshot this directory, the media tree is on a different
  # dataset. Snapshotting is disabled for that dataset vcia the
  # com.sun:auto-snapshot property on the dataset itself which I set
  # imperatively.
  fileSystems."/mnt/nas/media" = {
    device = "nas/media";
    fsType = "zfs";
    options = [ "nofail" ];
  };

  services.prometheus.exporters = {
    smartctl.enable = true;
    zfs.enable = true;
  };

  users.groups.media-writers = { };

  # Need media-writers ACL to support hardlinking with transmissions' output
  # (assuming protect_hardlinks=1)
  systemd.services.sonarr.serviceConfig.SupplementaryGroups = [
    config.users.groups.media-writers.name
  ];
  systemd.services.radarr.serviceConfig.SupplementaryGroups = [
    config.users.groups.media-writers.name
  ];

  systemd.tmpfiles.settings = {
    "10-mnt-nas-media" = {
      "/mnt/nas/media" = {
        z = {
          group = "media-writers";
          mode = "0775";
          user = "root";
        };
      };
      "/mnt/nas/media/transmission" = {
        Z = {
          group = "media-writers";
          mode = "0775";
          user = "root";
        };
      };
    };
  };

  # CIFS doesn't support file notifications so the Jellyfin watcher doesn't
  # notice new files. Crazy hack to fix it: Watch locally and trigger rescans
  # via the API :)
  # TODO: this is coupled with arr.nix, probably there should be an option to
  # report the directories to watch.
  age.secrets.jellarr-api-key.file = ../../secrets/jellarr-api-key.age;
  systemd.services.jellyfin-notifier = {
    description = "Watchexec Jellyfin API notifier";
    # I don't think depnding on a .mount unit like this is correct lmao
    after = [
      "network.target"
      "run-agenix.d.mount"
    ];
    unitConfig.RequiresMountsFor = [ "/mnt/nas/media" ];
    wantedBy = [ "multi-user.target" ];
    # Putting watchexec in here doesn't work since this PATH isn't used execute
    # the ExecStart, the ExecStart command is just executed with this PATH.
    path = [ pkgs.curl ];
    serviceConfig = {
      ExecStart =
        let
          jellyfinUrl =
            with homelab.servers.jellyfin;
            "http://${networking.hostName}.fritz.box:${builtins.toString bjackman.jellyfin.httpPort}";
          # watchexec prints the command it's running, which is useful, but it
          # risks leaking the API key into the journal. So put the actual key
          # read + update into its own little script.
          refreshScript = pkgs.writeShellScript "jellyin-refresh-library" ''
            set -eu -o pipefail
            key=$(cat ${config.age.secrets.jellarr-api-key.path})
            curl -f -X POST "${jellyfinUrl}/Library/Refresh?api_key=$key" -d "" 2>&1;
          '';
        in
        # --shell=none stops watchexec from trying to use a shell from $PATH,
        # since there isn't one in the service environment.
        "${pkgs.watchexec}/bin/watchexec --debounce 3s "
        + "--watch /mnt/nas/media/radarr --watch /mnt/nas/media/radarr "
        + "--shell=none -- ${refreshScript}";
      Restart = "always";
    };
  };

  powerManagement.powertop.enable = true;

  system.stateVersion = "25.11";
}
