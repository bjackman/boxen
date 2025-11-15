{
  pkgs,
  pkgsUnstable,
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

  config = {
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

    programs.rofi.enable = true;
    home.packages = [
      pkgsUnstable.bzmenu
      pkgsUnstable.pwmenu
      pkgs.rofi-screenshot
    ];
    # Define desktop entries for bzmenu and pwmenu so that we can access it
    # easily from the rofi dmenu. Not sure if this is really the proper way to
    # do this or not.
    # Note until we have this:
    # https://github.com/davatorium/rofi/pull/2122
    # We need to install silly font magic.
    xdg.desktopEntries.bzmenu = {
      name = "Bluetooth Menu";
      comment = "Manage Audio devices";
      exec = "pwmenu --launcher rofi";
      icon = "audio-card";
      terminal = false;
      type = "Application";
      categories = [
        "Settings"
        "System"
      ];
    };
    xdg.desktopEntries.pwmenu = {
      name = "Audio Menu (Pipewire)";
      comment = "Manage Audio devices";
      exec = "pwmenu --launcher rofi";
      icon = "bluetooth";
      terminal = false;
      type = "Application";
      categories = [
        "Settings"
        "System"
      ];
    };

    # Notification server. Works on both gLinux and NixOS.
    services.mako.enable = true;

    services.swayidle = {
      enable = true;
      # Lock screen when going to sleep.
      events = [
        {
          event = "before-sleep";
          command = "${lib.getExe config.programs.swaylock.package}";
        }
      ];
      # Debug mode - this is just basic logging, should be default.
      extraArgs = [ "-d" ];
      # Lock screen after being idle for a while.
      timeouts =
        let
          warnAfterSecs = 3 * 60;
          lockAfterSecs = 5;
          screenOffAfterSecs = 2 * 60;
          sleepAfterSecs = 3 * 60;
        in
        [
          {
            timeout = warnAfterSecs;
            command = ''${pkgs.libnotify}/bin/notify-send --expire-time ${
              toString (lockAfterSecs * 1000)
            } "Locking screen in ${toString (lockAfterSecs)}s"'';
          }
          {
            timeout = warnAfterSecs + lockAfterSecs;
            command = "${lib.getExe config.programs.swaylock.package}";
          }
          {
            timeout = warnAfterSecs + lockAfterSecs + screenOffAfterSecs;
            command = ''${pkgs.sway}/bin/swaymsg output "*" power off'';
            resumeCommand = ''${pkgs.sway}/bin/swaymsg output "*" power on'';
          }
          {
            timeout = warnAfterSecs + lockAfterSecs + screenOffAfterSecs;
            # `systemctl --user show-environment` shows that systemctl is in the
            # PATH for systemd services at least on NixOS.
            command = ''systemctl sleep'';
          }
        ];
    };

    programs.swaylock = {
      enable = true;
      settings = {
        image = ../hm_files/common/clouds_95.png;
        scaling = "fill";
        # Stop it from blocking suspend and stuff when called e.g. from swayidle before-sleep.
        daemonize = true;
      };
    };

    programs.kitty.enable = true;

    wayland.windowManager.sway = {
      enable = true;
      # Don't install the package, use the system once since that will have the
      # --unsupported-gpu flag if needed.
      package = null;
      # Include distro-local stuff. On NixOS this includes something
      # important. On Debian it includes the default background so we put it
      # in extraConfigEarly so that we can override it with our dank pix.
      extraConfigEarly = "include /etc/sway/config.d/*";
      # Lock when laptop lid closed
      extraConfig = ''
        bindswitch lid:on exec ${lib.getExe config.programs.swaylock.package}

        # These apps open on specific workspaces. This can be confusing if it
        # doesn't also focus that workspace, since the app opens but you can't
        # see it. So also explicitly set them to focus when opened. I think this
        # is already the default when it opens on the current workspace. I can't
        # figure out how to make this "focus workspace on open" the global
        # default, but I guess it's only an issue for these specific apps.
        for_window [app_id=kitty|firefox|dev.zed.Zed|Code] focus
        # This lets apps focus themselves unconditionally.
        focus_on_window_activation focus
      '';
      config = rec {
        bars = [ ];
        modifier = "Mod4";
        terminal = "kitty --session ${pkgs.writeText "fish.kitty-session" "launch fish"}";
        menu = "rofi -show drun";
        # Put my absolute boys on their home workspace by default. Update the
        # for_window above if you change this.
        # Use swaymsg -t get_tree to get the app_id you want.
        assigns = {
          "browser" = [
            { app_id = "firefox"; }
            { app_id = "google-chrome"; }
          ];
          "terminal" = [ { app_id = "kitty"; } ];
          "editor" = [
            { app_id = "dev.zed.Zed"; }
            { class = "Code"; }
          ];
        };
        # We can set global display settings here. Individual outputs will be
        # configured in per-machine modules.
        output."*" = {
          background = "${../hm_files/common/clouds.png} fill";
        };
        input."*".xkb_options = "compose:ralt";
        input."type:touchpad".natural_scroll = "enable";
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

          "${modifier}+c" = "exec ${lib.getExe config.programs.swaylock.package}";

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
            key: workspace:
            lib.nameValuePair "${modifier}+shift+${key}" "move window to workspace ${workspace}; workspace ${workspace}"
          ) workspaces)
        );
      };
    };
  };
}
