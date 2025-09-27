{ pkgs, ... }:
{
  programs.waybar.enable = true;
  # To make default Waybar configuration usable;
  home.packages = [ pkgs.font-awesome ];
}
