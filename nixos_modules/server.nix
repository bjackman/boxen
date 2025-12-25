# For machines that I only use via SSH.
{ lib, config, ... }:
{
  imports = [
    ./ssh-server.nix
  ];

  # There won't be a login password on this machine, all SSH all day.
  security.sudo.wheelNeedsPassword = false;

  # Recover remotely from kernel issues.
  boot.kernelParams = [
    "kernel.nmi_watchdog=1"
    "kernel.panic=10"
  ];
  # Recover remotely from higher-level issues like resource exhaustion.
  # I've tested this on a Pi5 against this which causes ZFS to shit the bed:
  #   ls /mnt/nas/.zfs/snapshot/*/media
  # Unfortunately I can't find any way the reset is directly recorded on the Pi,
  # I think the platform is just a bit shit. Part of the reason for this may be
  # that the Pi uses reboot=w. Whatever.
  services.watchdogd.enable = true;
}
