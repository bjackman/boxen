{
  config,
  pkgs,
  lib,
  modulesPath,
  nixos-hardware,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../pc.nix
    ../sway.nix
    ./incus.nix
    ./hardware-configuration.nix
    nixos-hardware.nixosModules.framework-amd-ai-300-series
  ];

  networking.hostName = "fw13";

  services.automatic-timezoned.enable = true;
  # automatic-timezoned dependson this GeoClue service which is a system to
  # figure out your location. That system has this thing called an "agent" that
  # integrates with your desktop; I'm not sure exactly what it does. If the
  # desktop doesn't implement the relevant dbus service then GeoClue won't work
  # so you need this "demo agent" thing. If Gnome gets enabled then the Gnome
  # NixOS module will clash with this setting - if we need a system where
  # GeoClue works on both Gnome and non-Gnome, I dunno how to achieve that.
  services.geoclue2.enableDemoAgent = true;

  programs.steam.enable = true;

  system.stateVersion = "25.05";
}
