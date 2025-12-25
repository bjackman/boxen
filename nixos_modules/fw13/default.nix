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
    ../pc.nix
    ../sway.nix
    ../iap.nix
    ./hardware-configuration.nix
    nixos-hardware.nixosModules.framework-amd-ai-300-series
  ];

  networking.hostName = "fw13";

  time.timeZone = "Europe/London";

  programs.steam.enable = true;

  system.stateVersion = "25.05";
}
