# TODO:
# - [x] Move hyprland config to Nix
# - [x] Figure out if I need an XDG portal and set one up.
# - [x] Make it derk mode
# - [ ] Get a status bar working.
#   - [ ] Set up battery icon if on laptop
#   - [x] Make power control work
#   - [x] Make it look nice
# - [x] Ensure bluetooth / sound / NetworkManager stuff is all usable
# - [x] Get a launcher working
# - [x] Figure out workspace workflow for desktop:
#       - super+b/n/m to switch to browser/terminal/editor workspaces
#       - super+shift+b/n/m to move a window to the corresponding workspace
#       - super+shift+h/l to move workspaces left and right between monitors
# - [ ] Document it for myself
# - [ ] Figure out how to dynamically create workspaces
# - [ ] Figure out how to dynamically enable/disable third monitor
# - [ ] Figure out an "overview" mechanism like Gnome has. I tried this:
#       https://code.hyprland.org/hyprwm/hyprland-plugins/src/branch/main/hyprexpo
#       which is an official plugin that's supposed to this but I just got an
#       error saying "hyrexpo:expo" wasn't valid, I guess I didn't install it
#       properly.
# - [x] Set up a lock screen
# - [ ] Make notifications work
#   - I can get notifications via `notify-send` but Firefox won't send them via
#     DBus.
# - [ ] Make screensharing work
#   - [x] In Firefox
#   - [ ] In Chrome
# - [x] Make Spotify work
# - [x] Figure out if I really wanna start services from hyprland, see about
#       using systemd properly.
# - [ ] Fix the cursor
# - [ ] Make hyperlinks work in terminal
# - [ ] Make it look like windows 98
# - [ ] Make volume/backlight control buttons work.
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
      assertion = osConfig.programs.hyprland.enable;
      message = "Must enable programs.hyprland.enable in NixOS config";
    }
    {
      assertion = osConfig.programs.hyprlock.enable;
      message = "Must enable programs.hyprlock.enable in NixOS config";
    }
  ];

  # This makes sure stuff like waybar is configured as part of the correct
  # systemd target, otherwise it gets put under graphical-session.target and
  # then doesn't work properly when restarting hyprland.
  wayland.systemd.target = "hyprland-session.target";

  # The launcher that hyprland is configured to use below.
  programs.wofi.enable = true;

  programs.hyprlock = {
    enable = true;
    settings = {
      backgrounds = [
        {
          path = "color";
          color = "rgba(100, 100, 100, 1.0)";
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "50, 50";
          position = "0, -100";
          halign = "center";
          valign = "center";

          # Show the user something is happening when they type
          on_key_press = "color: rgba(255, 255, 255, 1.0)";
          fade_duration = 0.1;

          capslock_color = "rgba(0, 0, 255, 1.0)";
          fail_color = "rgba(255, 0, 0, 1.0)";
          fail_transition_on_fail = true;
          fail_transition_duration = 0.5;
        }
      ];
    };
  };

  # Note this will probably also be affected by the flakiness commented on
  # programs.waybar.systemd.enable above.
  bjackman.wayland-services = {
    # This daemon translates DBus notification messages into "hyprctl notify"
    # calls, which just creates a notification natively inside hyprland.
    hyprnotify = "${pkgs.hyprnotify}/bin/hyprnotify";
  };

  # I don't really understand this bit. IIUC this only matters for Flatpak apps,
  # I haven't tried any so I don't know if this works, but adding it made a
  # warning go away when evaluating the config. Claude came up with this, I
  # think it may have cribbed it from here:
  # https://discourse.nixos.org/t/configuring-xdg-desktop-portal-with-home-manager-on-ubuntu-hyprland-via-nixgl/65287
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config = {
      common.default = "*";
      hyprland.default = [
        "hyprland"
        "gtk"
      ];
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    # Assume installed elsewhere, eithehr by NixOS module or non-Nix setup.
    package = null;
    settings = {
      # TODO: Switch to monitorv2 once we have 0.50.
      monitor = [
        # https://wiki.hypr.land/Configuring/Monitors/ recommends this, which
        # apparently defines a fallback rule that puts any unknown monitor to
        # the right of the others
        ", preferred, auto, 1"
      ];
      # The rest of this is adapted from the default configuration file.
      "$terminal" = "kitty";
      "$fileManager" = "nautilus";
      "$menu" = "wofi --show drun";
      env = [
        # TODO: what do these do?
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        # Dark theme configuration
        "GTK_THEME,Adwaita:dark"
        "QT_STYLE_OVERRIDE,adwaita-dark"
      ];
      general = {
        gaps_in = 5;
        gaps_out = 5;
        border_size = 2;

        # Damn, can't figure out how to make window borders have the "raised
        # border effect". You can only give them a single colour or global
        # gradient :(
        "col.active_border" = "rgba(c0c0c0ff)";
        "col.inactive_border" = "rgba(909090ff)";

        # Set to true enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false;
        # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = false;
        layout = "dwindle";
      };
      decoration = {
        # Change transparency of focused and unfocused windows
        active_opacity = 1.0;
        inactive_opacity = 1.0;
      };
      # https://wiki.hyprland.org/Configuring/Variables/#animations
      animations = {
        enabled = "yes, please :)";

        # Default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

        bezier = [
          "easeOutQuint,0.23,1,0.32,1"
          "easeInOutCubic,0.65,0.05,0.36,1"
          "linear,0,0,1,1"
          "almostLinear,0.5,0.5,0.75,1.0"
          "quick,0.15,0,0.1,1"
        ];

        animation = [
          "global, 1, 10, default"
          "border, 1, 5.39, easeOutQuint"
          "windows, 1, 4.79, easeOutQuint"
          "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
          "windowsOut, 1, 1.49, linear, popin 87%"
          "fadeIn, 1, 1.73, almostLinear"
          "fadeOut, 1, 1.46, almostLinear"
          "fade, 1, 3.03, quick"
          "layers, 1, 3.81, easeOutQuint"
          "layersIn, 1, 4, easeOutQuint, fade"
          "layersOut, 1, 1.5, linear, fade"
          "fadeLayersIn, 1, 1.79, almostLinear"
          "fadeLayersOut, 1, 1.39, almostLinear"
          "workspaces, 1, 1.94, almostLinear, fade"
          "workspacesIn, 1, 1.21, almostLinear, fade"
          "workspacesOut, 1, 1.94, almostLinear, fade"
        ];
      };

      # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
      dwindle = {
        pseudotile = true; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true; # You probably want this
      };

      # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
      master = {
        new_status = "master";
      };

      # https://wiki.hyprland.org/Configuring/Variables/#misc
      misc = {
        force_default_wallpaper = -1; # Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo = false; # If true disables the random hyprland logo / anime girl background. :(
      };

      # https://wiki.hyprland.org/Configuring/Variables/#input
      input = {
        kb_layout = "us";
        kb_variant = "";
        kb_model = "";
        kb_options = "";
        kb_rules = "";

        follow_mouse = 1;

        sensitivity = 0; # -1.0 - 1.0, 0 means no modification.

        touchpad = {
          natural_scroll = false;
        };
      };

      # https://wiki.hyprland.org/Configuring/Variables/#gestures
      gestures = {
        workspace_swipe = false;
      };

      # See https://wiki.hyprland.org/Configuring/Keywords/
      "$mainMod" = "SUPER"; # Sets "Windows" key as main modifier

      # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
      bind = [
        "$mainMod, Q, exec, $terminal"
        "$mainMod, C, killactive,"
        "$mainMod, E, exit,"
        "$mainMod, F, exec, $fileManager"
        "$mainMod, V, togglefloating,"
        "$mainMod, R, exec, $menu"
        "$mainMod, P, pseudo," # dwindle
        "$mainMod, J, togglesplit," # dwindle

        # Move focus with mainMod + arrow keys
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        # And with vim binds
        "$mainMod, H, movefocus, l"
        "$mainMod, L, movefocus, r"
        "$mainMod, K, movefocus, d"
        "$mainMod, J, movefocus, d"

        # Switch workspaces with mainMod + [0-9]
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"

        # Move active window to a workspace with mainMod + SHIFT + [0-9]
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, 0, movetoworkspace, 10"

        # Scroll through existing workspaces with mainMod + scroll
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"

        # Hardcoded named workspaces for my absolute boys
        "$mainMod SHIFT, B, movetoworkspace, name:browser"
        "$mainMod SHIFT, N, movetoworkspace, name:terminal"
        "$mainMod SHIFT, M, movetoworkspace, name:editor"
        "$mainMod, B, workspace, name:browser"
        "$mainMod, N, workspace, name:terminal"
        "$mainMod, M, workspace, name:editor"

        # Bindings to move workspaces between monitors
        "$mainMod SHIFT, L, movecurrentworkspacetomonitor, r"
        "$mainMod SHIFT, H, movecurrentworkspacetomonitor, l"
        "$mainMod, S, swapactiveworkspaces, current +1"

        # Locky locky
        "$mainMod, O, exec, hyprlock"
      ];

      windowrulev2 = [
        # Open my absolute boys on their named workspaces
        "workspace name:browser, class:^(firefox)$"
        "workspace name:terminal, class:^(kitty)$"
        "workspace name:editor, class:^(dev.zed.Zed)$"

        # Don't tile the blueman window
        "float, class:^(.blueman-manager-wrapped)$"
      ];

      # Laptop multimedia keys for volume and LCD brightness
      bindel = [
        ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
      ];

      # Move/resize windows with mainMod + LMB/RMB and dragging
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      # Ignore maximize requests from apps. You'll probably like this.
      windowrule = [
        "suppressevent maximize, class:.*"
        # Fix some dragging issues with XWayland
        "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
      ];

      # Start my absolute boys on startup
      exec-once = [
        "kitty"
        "firefox"
        "zeditor"
      ];
    };
  };
}
