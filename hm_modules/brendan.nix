{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = with pkgs; [
      pkgsUnstable.claude-code
      mosh
      file
      tree
      pstree
      btop
      libnotify # Useful for testing when faffing around with hyprnotify
      spotify
      imagemagick
      signal-desktop
    ];
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };
}
