{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };
}
