{
  pkgs,
  config,
  lib,
  ...
}@args:
let
  isNixOS = args ? osConfig;
  osConfig = if isNixOS then args.osConfig else { };
in
{
  imports = [
    ./wayland-services.nix
    ./waybar.nix
  ];

  assertions = lib.optionals isNixOS [
    {
      assertion = osConfig.programs.sway.enable;
      message = "Must enable programs.sway.enable in NixOS config";
    }
  ];

  # This makes sure stuff like waybar is configured as part of the correct
  # systemd target, otherwise it gets put under graphical-session.target and
  # then doesn't work properly when restarting hyprland.
  wayland.systemd.target = "sway-session.target";

  # Note this will probably also be affected by the flakiness commented on
  # programs.waybar.systemd.enable above.
  bjackman.wayland-services = {
    # Don't know why we need to run a program for this lol. It sets the
    # wallpaper then sits there forever.
    swaybg = "${pkgs.swaybg}/bin/swaybg -i ${../hm_files/common/ibm_wallpaper.png}";
  };

  wayland.windowManager.sway = {
    enable = true;
    config = rec {
      bars = [];
      modifier = "Mod4";
      keybindings = {
        "${modifier}+q" = "kill";
        "${modifier}+c" = "exec swaylock --indicator-caps-lock --color 000000";

        # Dedicated workspaces for my absolute boys. mod+letter switches to the
        # workspace. mod+shift+letter moves the window to it then focuses it.
        "${modifier}+b" = "workspace browser";
        "${modifier}+shift+b" = "move window to workspace browser; workspace browser";
        "${modifier}+n" = "workspace terminal";
        "${modifier}+shift+n" = "move window to workspace terminal; workspace terminal";
        "${modifier}+m" = "workspace editor";
        "${modifier}+shift+m" = "move window to workspace editor; workspace editor";
      };
    };
    # Include distro-local stuff. On NixOS this includes something important.
    extraConfig = "include /etc/sway/config.d/*";
  };
}
