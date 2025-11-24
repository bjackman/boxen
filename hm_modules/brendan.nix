{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = with pkgs; [
      mosh
      file
      tree
      pstree
      pciutils
      lshw
      btop
      spotify
      signal-desktop
      jq
      iw
    ];
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };
}
