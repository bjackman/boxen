{ config, ... }:
{
  imports = [
    ./dark-mode.nix
  ];
  bjackman.appConfigDirs.fish = [ ../hm_files/nixos/config/fish ];
  bjackman.configCheckout = "${config.home.homeDirectory}/src/boxen";
  programs.firefox.enable = true;
  programs.vscode.enable = true;
}
