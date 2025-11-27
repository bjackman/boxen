{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./common.nix
    ./brendan.nix
    ./sway.nix
    ./home-monitors.nix
  ];
  programs.zed-editor = {
    enable = true;
    package = pkgsUnstable.zed-editor;
  };
  xdg.configFile."monitors.xml".source = ../nixos_files/chungito/monitors.xml;
}
