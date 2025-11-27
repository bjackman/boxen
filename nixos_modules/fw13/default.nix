{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    ../brendan.nix
    ../pc.nix
    ../sway.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "fw13";

  time.timeZone = "Europe/London";

  system.stateVersion = "25.05";
}
