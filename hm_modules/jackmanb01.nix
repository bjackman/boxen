# Corp laptop
{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./jackmanb.nix
    ./sway.nix
    ./monitors.nix
    ./non-nixos-gl.nix
  ];

  wayland.windowManager.sway.config = {
    keybindings = {
      # Set up initial connection to remote multiplexing server
      "${config.wayland.windowManager.sway.config.modifier}+Ctrl+Return" = "exec wezterm connect bj";
      # Add a window on the remote multiplexing server
      "${config.wayland.windowManager.sway.config.modifier}+Shift+Return" =
        "exec ssh bj /usr/local/google/home/jackmanb/.nix-profile/bin/wezterm cli spawn --new-window fish";
    };
  };

  # Desktop entry to run Chrome forcing native Wayland mode, with a workaround
  # flag to make fractional scaling work.
  xdg.desktopEntries.chrome-wayland = {
    name = "Google Chrome (Wayland)";
    genericName = "Web Browser";
    exec = "google-chrome --ozone-platform=wayland --disable-features=WaylandFractionalScaleV1 %U";
    terminal = false;
    categories = [
      "Network"
      "WebBrowser"
    ];
    icon = "google-chrome";
    settings = {
      StartupNotify = "true";
    };
  };
}
