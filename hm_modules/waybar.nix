{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.waybar = {
    enable = true;
    # Note: this is kinda flaky, hmm:
    # https://github.com/nix-community/home-manager/issues/7895
    systemd.enable = true;
    settings.main = {
      # This is basically just the default config with bits deleted or switched
      # out for hyprland stuff instead of sway.
      height = 30;
      spacing = 4;
      position = "bottom";
      modules-left = [
        "custom/power"
        "hyprland/workspaces"
        "sway/workspaces"
      ];
      modules-center = [
        "hyprland/window"
        "sway/window"
      ];
      modules-right = [
        "pulseaudio"
        "power-profiles-daemon"
        "cpu"
        "memory"
        "temperature"
        "backlight"
        "keyboard-state"
        "clock"
        # We're gonna run nm-applet which should show up in the tray, but also
        # put the network module next to it since it has some nice info there.
        "network"
        "tray"
      ];
      keyboard-state = {
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
        # The spaces are so that the icon can be added as the CSS
        # background-image, lmao
        format = "<b>      Start</b>";
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
          shutdown = "poweroff";
          reboot = "reboot";
          suspend = "systemctl suspend";
          hibernate = "systemctl hibernate";
        };
      };
    };
    style = pkgs.replaceVars ./waybar.css { start-icon-png = ../hm_files/common/start.png; };
  };
  home.packages = with pkgs; [
    # To make default Waybar configuration usable;
    font-awesome
    # Installing these packages explicitly (instead of just referring to the
    # binary from the systemd service definition) seems to make sure the
    # nm-applet icons are available for the tray, I haven't looked into why nor
    # even proven this hypothesis properly.
    networkmanagerapplet
    blueman
  ];

  bjackman.wayland-services = {
    # Figured this out from https://www.reddit.com/r/hyprland/comments/14dj80q/comment/joq52rg/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
    nm-applet = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
    # This is kinda yucky and ugly but whatever, need something that works.
    blueman-applet = "${pkgs.blueman}/bin/blueman-applet";
  };
}
