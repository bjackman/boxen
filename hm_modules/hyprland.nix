{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.main = {
      # This is basically just the default config with bits deleted or switched
      # out for hyprland stuff instead of sway.
      height = 30;
      spacing = 4;
      modules-left = [
        "hyprland/workspaces"
      ];
      modules-center = [
        "hyprland/window"
      ];
      modules-right = [
        "pulseaudio"
        "network"
        "power-profiles-daemon"
        "cpu"
        "memory"
        "temperature"
        "backlight"
        "keyboard-state"
        "clock"
        "tray"
        "custom/power"
      ];
      keyboard-state = {
        numlock = true;
        capslock = true;
        format = "{name} {icon}";
        format-icons = {
          locked = "";
          unlocked = "";
        };
      };
      tray = {
        spacing = 10;
      };
      clock = {
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        format-alt = "{:%Y-%m-%d}";
      };
      cpu = {
        format = "{usage}% ";
        tooltip = false;
      };
      memory = {
        format = "{}% ";
      };
      temperature = {
        critical-threshold = 80;
        format = "{temperatureC}°C {icon}";
        format-icons = [
          ""
          ""
          ""
        ];
      };
      backlight = {
        format = "{percent}% {icon}";
        format-icons = [
          ""
          ""
          ""
          ""
          ""
          ""
          ""
          ""
          ""
        ];
      };
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        format-full = "{capacity}% {icon}";
        format-charging = "{capacity}% ";
        format-plugged = "{capacity}% ";
        format-alt = "{time} {icon}";
        format-icons = [
          ""
          ""
          ""
          ""
          ""
        ];
      };
      "battery#bat2" = {
        bat = "BAT2";
      };
      power-profiles-daemon = {
        format = "{icon}";
        tooltip-format = "Power profile: {profile}\nDriver: {driver}";
        tooltip = true;
        format-icons = {
          default = "";
          performance = "";
          balanced = "";
          power-saver = "";
        };
      };
      network = {
        format-wifi = "{essid} ({signalStrength}%) ";
        format-ethernet = "{ipaddr}/{cidr} ";
        tooltip-format = "{ifname} via {gwaddr} ";
        format-linked = "{ifname} (No IP) ";
        format-disconnected = "Disconnected ⚠";
        format-alt = "{ifname}: {ipaddr}/{cidr}";
      };
      pulseaudio = {
        format = "{volume}% {icon} {format_source}";
        format-bluetooth = "{volume}% {icon} {format_source}";
        format-bluetooth-muted = " {icon} {format_source}";
        format-muted = " {format_source}";
        format-source = "{volume}% ";
        format-source-muted = "";
        format-icons = {
          headphone = "";
          hands-free = "";
          headset = "";
          phone = "";
          portable = "";
          car = "";
          default = [
            ""
            ""
            ""
          ];
        };
        on-click = "pavucontrol";
      };
      "custom/power" = {
        # I'm not sure why I need the spaces around this icon, the other modules
        # don't need it. I think maybe something to do with the custom module
        # not having default styling? I'm not sure whether I've actually applied
        # styling.
        format = " ⏻ ";
        tooltip = false;
        menu = "on-click";

        # Copied from
        # https://github.com/Alexays/Waybar/blob/41de8964f1e3278edf07902ad68ca5e01e7abeeb/resources/custom_modules/power_menu.xml
        menu-file = pkgs.writeText "power_menu.xml" ''
          <?xml version="1.0" encoding="UTF-8"?>
          <interface>
            <object class="GtkMenu" id="menu">
              <child>
                <object class="GtkMenuItem" id="suspend">
                  <property name="label">Suspend</property>
                </object>
              </child>
                <child>
                  <object class="GtkMenuItem" id="hibernate">
                    <property name="label">Hibernate</property>
                  </object>
                </child>
              <child>
                <object class="GtkMenuItem" id="shutdown">
                  <property name="label">Shutdown</property>
                </object>
              </child>
              <child>
                <object class="GtkSeparatorMenuItem" id="delimiter1"/>
              </child>
              <child>
                <object class="GtkMenuItem" id="reboot">
                  <property name="label">Reboot</property>
                </object>
              </child>
            </object>
          </interface>
        '';
        menu-actions = {
          shutdown = "shutdown";
          reboot = "reboot";
          suspend = "systemctl suspend";
          hibernate = "systemctl hibernate";
        };
      };
    };
  };
  # To make default Waybar configuration usable;
  home.packages = [ pkgs.font-awesome ];

  # The launcher that hyprland is configured to use below.
  programs.wofi.enable = true;

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
        gaps_out = 20;
        border_size = 2;
        # https://wiki.hyprland.org/Configuring/Variables/#variable-types for info about colors
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        # Set to true enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false;
        # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = false;
        layout = "dwindle";
      };
      decoration = {
        rounding = 10;
        rounding_power = 2;
        # Change transparency of focused and unfocused windows
        active_opacity = 1.0;
        inactive_opacity = 1.0;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        # https://wiki.hyprland.org/Configuring/Variables/#blur
        blur = {
          enabled = true;
          size = 3;
          passes = 1;

          vibrancy = 0.1696;
        };
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

        # Example special workspace (scratchpad)
        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"

        # Scroll through existing workspaces with mainMod + scroll
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
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
    };
  };
}
