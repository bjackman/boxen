{ config, pkgs, ... }:

{
  home = {
    username = "niamh";
    homeDirectory = "/home/niamh";
    stateVersion = "25.11";
  };
  programs.home-manager.enable = true;
}
