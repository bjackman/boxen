{ pkgs, ... }:
{
  imports = [
    ./common.nix
    ./hyprland.nix
  ];
  users.users.brendan = {
    isNormalUser = true;
    description = "Brendan Jackman";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true;
}
