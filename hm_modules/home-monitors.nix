{
  config,
  pkgsUnstable,
  ...
}:
{
  # TODO: Switch to monitorv2 once we have 0.50.
  wayland.windowManager.hyprland.settings.monitor = [
    "desc:Dell Inc. DELL P2720DC 81WTK01403MS,preferred,auto,auto"
    "desc:Google Inc. P2718EC C9240002,preferred,auto-left,auto"
  ];

  # Get the description from "swaymsg -t get_outputs"
  wayland.windowManager.sway.config.output = {
    # On the left
    "Google Inc. P2718EC C9240002" = {
      position = "0 0";
    };
    # One at my mum's place:
    "LG Electronics LG ULTRAFINE 508NTGYKX551" = {
      position = "0 0";
      scale = "1.5";
    };
    # To the right of the Google one
    "Dell Inc. DELL P2720DC 81WTK01403MS" = {
      position = "2560 0";
    };
  };
}
