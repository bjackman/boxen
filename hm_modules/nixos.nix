{ ... }:
{
  common.appConfigDirs.fish = [ ../hm_files/nixos/config/fish ];
  programs.firefox.enable = true;
  programs.kitty.enable = true;
  programs.swaylock.enable = true;
}
