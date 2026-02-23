{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = [
      pkgs.llm-agents.gemini-cli
    ];
  };
  programs.git.settings.user.email = "bhenryj0117@gmail.com";
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };
}
