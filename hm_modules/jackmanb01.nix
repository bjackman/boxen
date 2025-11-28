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
    ./home-monitors.nix
    ./non-nixos-gl.nix
  ];

  wayland.windowManager.sway.config = {
    output = {
      # Monitors at the office:
      # Center monitor
      "Lenovo Group Limited P27h-20 V906YLCP" = {
        position = "0 0";
      };
      # To the right of the Lenovo one
      "Samsung Electric Company LS27A600U HNMR402251" = {
        position = "2560 0";
      };
      # Below the lenovo one
      "BOE 0x0C00 Unknown" = {
        position = "0 1440";
      };
    };
    keybindings = {
      # Set up initial connection to remote multiplexing server
      "${config.wayland.windowManager.sway.config.modifier}+Ctrl+Return" = "exec wezterm connect bj";
      # Add a window on the remote multiplexing server
      "${config.wayland.windowManager.sway.config.modifier}+Shift+Return" =
        "exec ssh bj /usr/local/google/home/jackmanb/.nix-profile/bin/wezterm cli spawn --new-window fish";
    };
  };
}
