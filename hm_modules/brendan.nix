{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = with pkgs; [
      pkgsUnstable.gemini-cli
      pkgsUnstable.claude-code
      mosh
      file
      tree
    ];
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
  programs.vim.enable = true;
}
