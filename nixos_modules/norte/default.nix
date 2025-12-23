{
  config,
  modulesPath,
  nixos-raspberrypi,
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
    ../transmission.nix
    ./nfs-server.nix
  ];

  boot.loader.raspberryPi.bootloader = "kernel";

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

  # AI says ZFS needs a machine ID. Somehow even before I set this, there was a
  # hostId already set when I evaliated the configuration. I dunno if this is
  # some weird nixos-raspberrypi shit or what. Anyway let's just set a stable
  # fixed one to keep things sane.
  networking.hostId = "39bb2a74";
  boot.supportedFilesystems.zfs = true;
  # The ZFS pool attached to this system was created before I installed NixOS,
  # using Ubuntu.
  # Following the suggestion of AI, I set mountpoint=legacy for each of the
  # datasets to stop zfs tools from auto-mounting them.
  boot.zfs.extraPools = [ "nas" ];
  fileSystems."/mnt/nas" = {
    device = "nas";
    fsType = "zfs";
  };
  services.zfs.autoScrub.enable = true;
  services.zfs.autoSnapshot.enable = true;

  users.groups.media-writers = { };
  systemd.services.transmission.serviceConfig = {
    SupplementaryGroups = [ "media-writers" ];
    ReadWritePaths = [ "/mnt/nas/media" ];
  };
  services.transmission.settings.download-dir = "/mnt/nas/media";

  powerManagement.powertop.enable = true;

  system.stateVersion = "25.11";
}
