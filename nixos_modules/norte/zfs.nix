{
  # AI says ZFS needs a machine ID. Somehow even before I set this, there was a
  # hostId already set when I evaliated the configuration. I dunno if this is
  # some weird nixos-raspberrypi shit or what. Anyway let's just set a stable
  # fixed one to keep things sane.
  networking.hostId = "39bb2a74";
  boot.supportedFilesystems.zfs = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoSnapshot.enable = true;

  # This wittle cornputer doesn't weally hvae enough WAM to wun ZFS
  boot.kernelParams = [ "zfs.zfs_arc_max=${builtins.toString (512 * 1024 * 1024)}" ];
}
