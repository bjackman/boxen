{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    ../common.nix
    ../brendan.nix
    ../pc.nix
    ../sway.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "fw13";

  time.timeZone = "Europe/London";

  programs.steam.enable = true;

  system.stateVersion = "25.05";
}
