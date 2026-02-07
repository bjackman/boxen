{
  pkgs,
  config,
  modulesPath,
  nixos-raspberrypi,
  otherConfigs,
  ...
}:
let
  nfsCfg = config.bjackman.nfsServer;
in
{
  # This was figured out with great pain and anguish, not by reading docs.
  imports = [
    nixos-raspberrypi.nixosModules.sd-image
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    ../brendan.nix
    ../server.nix
    ../common.nix
    ../transmission.nix
    ../users.nix
    ../node-exporter.nix
    ../restic-exporter.nix
    ../iap.nix
    # Need to run Radarr locally so it can do hardlinks
    ../radarr.nix
    ./restic-exporter.nix
    ./nfs-server.nix
    ./samba-server.nix
    ./sftp-server.nix
    ./zfs.nix
    # Warning: she doesn't have vewwy much WAM uwu
    # Check https://perses.home.yawn.io/projects/homelab/dashboards/node-exporter-nodes?var-instance=norte
  ];

  boot.loader.raspberry-pi.bootloader = "kernel";

  networking.hostName = "norte";

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
  };

  # The ZFS pool attached to this system was created before I installed NixOS,
  # using Ubuntu.
  # Following the suggestion of AI, I set mountpoint=legacy for each of the
  # datasets to stop zfs tools from auto-mounting them.
  boot.zfs.extraPools = [ "nas" ];
  fileSystems."/mnt/nas" = {
    device = "nas";
    fsType = "zfs";
  };
  # /mnt/nas directly mounts the root dataset of the pool. In order to avoid
  # needing to snapshot this directory, the media tree is on a different
  # dataset. Snapshotting is disabled for that dataset vcia the
  # com.sun:auto-snapshot property on the dataset itself which I set
  # imperatively.
  fileSystems."/mnt/nas/media" = {
    device = "nas/media";
    fsType = "zfs";
  };

  services.prometheus.exporters = {
    smartctl.enable = true;
    zfs.enable = true;
  };

  users.groups.media-writers = { };
  systemd.services.transmission.serviceConfig = {
    SupplementaryGroups = [ "media-writers" ];
    ReadWritePaths = [ nfsCfg.mediaDir ];
  };
  services.transmission.settings = {
    download-dir = "/mnt/nas/media/transmission/downloads";
    incomplete-dir = "/mnt/nas/media/transmission/incomplete";
  };
  systemd.tmpfiles.settings."10-transmission-incomplete" =
    let
      service = config.systemd.services.transmission.serviceConfig;
      def = {
        user = service.User;
        group = service.Group;
        mode = "0755";
      };
    in
    {
      "${config.services.transmission.settings.incomplete-dir}".d = def;
      "${config.services.transmission.settings.download-dir}".d = def;
    };

  # NFS/CIFS doesn't support file notifications so the Jellyfin watcher doesn't
  # notice new files. Crazy hack to fix it: Watch locally and trigger rescans
  # via the API :)
  age.secrets.jellarr-api-key.file = ../../secrets/jellarr-api-key.age;
  systemd.services.jellyfin-notifier = {
    description = "Watchexec Jellyfin API notifier";
    # I don't think depnding on a .mount unit like this is correct lmao
    after = [
      "network.target"
      "run-agenix.d.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    # Putting watchexec in here doesn't work since this PATH isn't used execute
    # the ExecStart, the ExecStart command is just executed with this PATH.
    path = [ pkgs.curl ];
    serviceConfig = {
      ExecStart =
        let
          jellyfinUrl =
            with otherConfigs.jellyfinServer;
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
        "${pkgs.watchexec}/bin/watchexec --debounce 3s --watch ${nfsCfg.mediaDir} --shell=none -- ${refreshScript}";
      Restart = "always";
    };
  };

  powerManagement.powertop.enable = true;

  system.stateVersion = "25.11";
}
