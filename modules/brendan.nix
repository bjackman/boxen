{ pkgs, ... }:
{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = [ pkgs.gemini-cli ];
  };
  programs.git.userEmail = "bhenryj0117@gmail.com";
}
