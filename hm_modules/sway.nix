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
    # Don't install the package, use the system once since that will have the
    # --unsupported-gpu flag if needed.
    package = null;
    config = rec {
      bars = [ ];
      modifier = "Mod4";
      terminal = "${pkgs.kitty}/bin/kitty";
      # Copy default keybindings from
      # https://github.com/NixOS/nixpkgs/blob/d916df777523d75f7c5acca79946652f032f633e/nixos/modules/programs/wayland/sway.nix
      keybindings = {
        "${modifier}+Return" = "exec ${config.wayland.windowManager.sway.config.terminal}";
        "${modifier}+Shift+q" = "kill";
        "${modifier}+d" = "exec ${config.wayland.windowManager.sway.config.menu}";

        "${modifier}+h" = "focus left";
        "${modifier}+j" = "focus down";
        "${modifier}+k" = "focus up";
        "${modifier}+l" = "focus right";

        "${modifier}+Left" = "focus left";
        "${modifier}+Down" = "focus down";
        "${modifier}+Up" = "focus up";
        "${modifier}+Right" = "focus right";

        "${modifier}+Shift+h" = "move left";
        "${modifier}+Shift+j" = "move down";
        "${modifier}+Shift+k" = "move up";
        "${modifier}+Shift+l" = "move right";

        "${modifier}+Shift+Left" = "move left";
        "${modifier}+Shift+Down" = "move down";
        "${modifier}+Shift+Up" = "move up";
        "${modifier}+Shift+Right" = "move right";

        "${modifier}+b" = "splith";
        "${modifier}+v" = "splitv";
        "${modifier}+f" = "fullscreen toggle";
        "${modifier}+a" = "focus parent";

        "${modifier}+s" = "layout stacking";
        "${modifier}+w" = "layout tabbed";
        "${modifier}+e" = "layout toggle split";

        "${modifier}+Shift+space" = "floating toggle";
        "${modifier}+space" = "focus mode_toggle";

        "${modifier}+Shift+minus" = "move scratchpad";
        "${modifier}+minus" = "scratchpad show";

        "${modifier}+Shift+c" = "reload";
        "${modifier}+Shift+e" =
          "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -b 'Yes, exit sway' 'swaymsg exit'";

        "${modifier}+r" = "mode resize";
      }
      // (
        let
          workspaces = {
            "1" = "number 1";
            "2" = "number 2";
            "3" = "number 3";
            "4" = "number 4";
            "5" = "number 5";
            "6" = "number 6";
            "7" = "number 7";
            "8" = "number 8";
            "9" = "number 9";
          };
        in
        (lib.mapAttrs' (
          key: workspace: lib.nameValuePair "${modifier}+${key}" "workspace ${workspace}"
        ) workspaces)
        // (lib.mapAttrs' (
          key: workspace: lib.nameValuePair "${modifier}+shift+${key}" "move window to workspace ${workspace}"
        ) workspaces)
      );
    };
    # Include distro-local stuff. On NixOS this includes something important.
    extraConfig = "include /etc/sway/config.d/*";
  };
}
