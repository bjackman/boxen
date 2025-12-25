# For machines that I only use via SSH.
{ lib, config, ... }:
{
  imports = [
    ./ssh-server.nix
  ];

  # There won't be a login password on this machine, all SSH all day.
  security.sudo.wheelNeedsPassword = false;

  boot.kernelParams = [
    "kernel.nmi_watchdog=1"
    "kernel.panic=10"
  ];
  services.watchdogd = {
    enable = true;
    settings.interval = 10;
  };
}
