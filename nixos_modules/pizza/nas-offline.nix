{ lib, ... }:
# TEMPORARY degraded mode: Norte (the NAS) is offline awaiting hardware
# replacement.
#
# Pizza mounts Norte's media share over CIFS as an automount (//norte/...,
# x-systemd.automount + nofail), so the mount unit itself doesn't block. The
# problem is the services that *touch* that mount during activation: with the
# NAS down, the first access triggers the automount, which then hangs against
# the dead server until the CIFS timeout and fails the unit -- which fails the
# whole `switch-to-configuration`, so deploy-rs rolls the deploy back.
#
# This module disables exactly the units that block on the dead NAS, so deploys
# succeed and everything NAS-independent keeps running (notably Jellyfin/IPTV,
# which never touches the share -- its library scan is async and non-fatal).
#
# To restore full service once Norte is back: remove the ./nas-offline.nix
# import from ./default.nix and redeploy.
{
  # Transmission's download/incomplete dirs live on the NAS mount; it blocks on
  # them at startup.
  services.transmission.enable = lib.mkForce false;

  # FileBrowser's root *is* the NAS mount (bjackman.sambaMounts.filebrowser) and
  # its preStart runs against it; it already flaps "due to Samba issues" when
  # the share is unavailable.
  services.filebrowser.enable = lib.mkForce false;

  # This tmpfiles rule d-creates /mnt/nas-media, which is the automount point
  # itself -- statting/creating it triggers a mount attempt against the dead NAS
  # during systemd-tmpfiles-setup. Drop it while the NAS is down.
  systemd.tmpfiles.settings."10-mnt-nas-media" = lib.mkForce { };
}
