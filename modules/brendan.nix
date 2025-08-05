{ pkgs, ... }:
{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = with pkgs; [
      gemini-cli
      mosh
    ];
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
}
