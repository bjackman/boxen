{ pkgs, ... }:
{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = [ pkgs.gemini-cli ];
  };
}
