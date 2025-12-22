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
    ./brendan.nix
    ./server.nix
    ./common.nix
    ./transmission.nix
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

  # Create /mnt/nas/media, let anyone read it. Members of media-writers can
  # write it. This is defined explicitly here while other subtrees aren't,
  # that's just coz they were created before I set up NixOS on this node.
  users.groups.media-writers = { };
  systemd.tmpfiles.settings = {
    "10-mnt-nas-media" = {
      "/mnt/nas/media" = {
        d = {
          group = "media-writers";
          mode = "0755";
          user = "root";
        };
      };
    };
  };
  # We are gonna set up an NFS server with anonuid and all_squash, which means
  # we don't care about the ID of whoever is accessing it we're just gonna
  # consider them as having this particular UID.
  # Create a user that we can use for this purpose, this way we know what the
  # UID means.
  users.users.nfs-media = {
    isSystemUser = true;
    group = "nfs-media";
    uid = 900;
  };
  users.groups.nfs-media.gid = 900;
  # WARNING: no_subtree_check means that if you know an inode number you can
  # leak files from outside of the exported directories (from the same
  # filesystem). Hopefully this is OK since we are restricting access to stuff
  # local to the LAN...?
  services.nfs.server = {
    enable = true;
    exports =
      let
        uid = builtins.toString config.users.users.nfs-media.uid;
        gid = builtins.toString config.users.groups.nfs-media.gid;
      in
      # WARNING: The path of this export is coupled with the client
      # configuration. If you change it you'll need to update the users too.
      ''
        /mnt/nas/media 192.168.0.0/16(ro,all_squash,anonuid=${uid},anongid=${gid},no_subtree_check)
      '';
  };
  networking.firewall.allowedTCPPorts = [ 2049 ];

  services.transmission.settings.download-dir = "/mnt/nas/media";

  powerManagement.powertop.enable = true;

  system.stateVersion = "25.11";
}
