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
  bjackman.configCheckout = "${config.home.homeDirectory}/src/boxen";
  programs.zed-editor = {
    enable = true;
    package = pkgsUnstable.zed-editor;
  };
  xdg.configFile."monitors.xml".source = ../nixos_files/chungito/monitors.xml;
}
