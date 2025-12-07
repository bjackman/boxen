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
      "${config.wayland.windowManager.sway.config.modifier}+Ctrl+Return" = "exec wezterm connect bj-jp";
      # Add a window on the remote multiplexing server
      "${config.wayland.windowManager.sway.config.modifier}+Shift+Return" =
        "exec ssh bj-jp /usr/local/google/home/jackmanb/.nix-profile/bin/wezterm cli spawn --new-window fish";
    };
  };
}
