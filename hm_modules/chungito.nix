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
  xdg.configFile."monitors.xml".source = ../nixos_files/chungito/monitors.xml;
}
