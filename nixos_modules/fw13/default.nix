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
    ./disko.nix
    # Can't use this module until we've set up boot.fileSystems...
    # ../impermanence.nix
  ];

  networking.hostName = "fw13";

  time.timeZone = "Europe/London";

  system.stateVersion = "25.05";
}
