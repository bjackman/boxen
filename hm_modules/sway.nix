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

  options = {
    bjackman.sway.lockScreenCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.swaylock}/bin/swaylock --color 888888";
      description = "Command to use to lock screen. Executed via 'a shell'.";
    };
  };

  config = {
    assertions = lib.optionals isNixOS [
      {
        assertion = osConfig.programs.sway.enable;
        message = "Must enable programs.sway.enable in NixOS config";
      }
      # We don't want to install it here because running the NixOS version of
      # Wayland apps on non-NixOS doesn't work.
      # Anyway we are over-asserting here, we don't actually need
      # programs.kitty.enable, so if you are installing it some other way feel
      # free to change this assertion.
      {
        assertion = config.programs.kitty.enable;
        message = "Must enable programs.kitty.enable in Home Manager config";
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
      swaybg = "${pkgs.swaybg}/bin/swaybg --mode fill --image ${../hm_files/common/clouds_95.png}";
    };

    programs.wofi.enable = true;

    # Notification server. Works on both gLinux and NixOS.
    services.mako.enable = true;

    services.swayidle = {
      enable = true;
      timeouts =
        let
          lockAfterSecs = 5 * 60;
          notifyWindow = 5;
        in
        [
          {
            timeout = lockAfterSecs - notifyWindow;
            command = ''${pkgs.libnotify}/bin/notify-send --expire-time ${toString (notifyWindow * 1000)} "Locking screen in ${toString notifyWindow}s"'';
          }
          {
            timeout = lockAfterSecs;
            command = config.bjackman.sway.lockScreenCommand;
          }
        ];
    };

    wayland.windowManager.sway = {
      enable = true;
      # Don't install the package, use the system once since that will have the
      # --unsupported-gpu flag if needed.
      package = null;
      config = rec {
        bars = [ ];
        modifier = "Mod4";
        terminal = "kitty --session ${pkgs.writeText "fish.kitty-session" "launch fish"}";
        menu = "wofi --show drun";
        # Put my absolute boys on their home workspace by default
        assigns = {
          "browser" = [ { app_id = "firefox"; } ];
          "terminal" = [ { app_id = "kitty"; } ];
          "editor" = [ { app_id = "dev.zed.Zed"; } ];
        };
        # Copy default keybindings from
        # https://github.com/NixOS/nixpkgs/blob/d916df777523d75f7c5acca79946652f032f633e/nixos/modules/programs/wayland/sway.nix
        keybindings = {
          "${modifier}+Return" = "exec ${config.wayland.windowManager.sway.config.terminal}";
          "${modifier}+t" = "kill";
          "${modifier}+d" = "exec ${config.wayland.windowManager.sway.config.menu}";

          "${modifier}+h" = "focus left";
          "${modifier}+j" = "focus down";
          "${modifier}+k" = "focus up";
          "${modifier}+l" = "focus right";

          "${modifier}+Left" = "focus left";
          "${modifier}+Down" = "focus down";
          "${modifier}+Up" = "focus up";
          "${modifier}+Right" = "focus right";

          "${modifier}+Shift+h" = "move workspace to output left";
          "${modifier}+Shift+j" = "move workspace to output down";
          "${modifier}+Shift+k" = "move workspace to output up";
          "${modifier}+Shift+l" = "move workspace to output right";

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

          "${modifier}+c" = "exec ${config.bjackman.sway.lockScreenCommand}";

          "XF86AudioRaiseVolume" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
          "XF86AudioLowerVolume" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
          "XF86AudioMute" = "exec ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
          "XF86AudioMicMute" = "exec ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle";
          "XF86MonBrightnessUp" = "exec brightnessctl set 10%+";
          "XF86MonBrightnessDown" = "exec brightnessctl set 10%-";
        }
        // (
          let
            workspaces = {
              "b" = "browser";
              "n" = "terminal";
              "m" = "editor";
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
            key: workspace:
            lib.nameValuePair "${modifier}+shift+${key}" "move window to workspace ${workspace}; workspace ${workspace}"
          ) workspaces)
        );
      };
      # Include distro-local stuff. On NixOS this includes something important.
      extraConfig = "include /etc/sway/config.d/*";
    };
  };
}
