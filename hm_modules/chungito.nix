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
    "desc:Dell Inc. DELL P2720DC 81WTK01403MS,preferred,auto,auto"
    "desc:Google Inc. P2718EC C9240002,preferred,auto-left,auto"
  ];
}
