{ pkgs, ... }:
{
  imports = [
    ./common.nix
  ];
  users.users.brendan = {
    isNormalUser = true;
    description = "Brendan Jackman";
    extraGroups = [
      "networkmanager"
      "wheel"
      # Required for hyprland stuff to be able to query capslock status.
      "input"
    ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true;
}
