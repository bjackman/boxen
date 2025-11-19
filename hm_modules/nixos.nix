{ ... }:
{
  imports = [
    ./dark-mode.nix
  ];
  bjackman.appConfigDirs.fish = [ ../hm_files/nixos/config/fish ];
  programs.firefox.enable = true;
  programs.vscode.enable = true;
}
