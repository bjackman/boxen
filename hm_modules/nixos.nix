{ ... }:
{
  imports = [
    ./dark-mode.nix
  ];
  common.appConfigDirs.fish = [ ../hm_files/nixos/config/fish ];
  programs.firefox.enable = true;
}
