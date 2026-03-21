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
  boot.kernelParams = [
    "zfs.zfs_arc_max=${builtins.toString (256 * 1024 * 1024)}"
    # I'm seeing OOMs from unreclaimable kernel allocations, AI says these
    # params would help to mitigate that. zfs_dirty_data_max apparently defaults
    # to 10% of system RAM but I was still seeing hundreds of megabytes
    # allocated from ZFS's ABD and SPL. AI says the dirty_data_max is just a
    # watermark and doesn't actually block ongoing requests, but hopefully
    # reducing it triggers writeback soon and reducing the number of active
    # async writes will also help the overhead stay down.
    # This is probably really bad for performance.
    "zfs.zfs_dirty_data_max=${toString (64 * 1024 * 1024)}"
    "zfs.zfs_vdev_async_write_max_active=1"
  ];
}
