{ pkgs, ... }:
{
  home.packages = [ pkgs.jetbrains-mono ];
  fonts.fontconfig.enable = true;

  programs.foot = {
    enable = true;
    settings = {
      main.font = "JetBrains Mono:size=11";
      scrollback.lines = 10000;
    };
  };
}
