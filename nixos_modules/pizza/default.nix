{
  config,
  pkgs,
  modulesPath,
  nixos-hardware,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../server.nix
    ./disko.nix
    "${modulesPath}/profiles/headless.nix"
    "${modulesPath}/profiles/minimal.nix"
    nixos-hardware.nixosModules.lenovo-thinkpad-t480
  ];

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

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Notes:
  #
  # I'm able to query DPMS (monitor power state) with:
  #
  #   grep . /sys/class/drm/card*-*/dpms
  #
  # This command will make that switch to "Off" but I don't see a dip in power
  # usage. I suspect that while the lid is closed, there is no power usage by
  # the monitor regardless of the logical state.
  #
  #   setterm --blank force --term linux < /dev/tty1 > /dev/tty1

  system.stateVersion = "25.11";
}
