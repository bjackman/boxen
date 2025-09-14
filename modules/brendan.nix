{ pkgs, pkgsUnstable, ... }:
{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = with pkgs; [
      pkgsUnstable.gemini-cli
      pkgsUnstable.claude-code
      mosh
    ];
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
}
