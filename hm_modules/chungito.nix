{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./common.nix
    ./brendan.nix
    ./hyprland.nix
  ];
  common.config-checkout = "${config.home.homeDirectory}/src/boxen";
  programs.zed-editor = {
    enable = true;
    package = pkgsUnstable.zed-editor;
  };

  # TODO: Switch to monitorv2 once we have 0.50.
  wayland.windowManager.hyprland.settings.monitor = [
    "HDMI-A-1,preferred,auto,auto"
    "HDMI-A-2,preferred,auto-left,auto"
  ];
}
