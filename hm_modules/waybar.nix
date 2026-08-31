{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.bjackman.waybar.showKeyboardLayout = lib.mkEnableOption "keyboard layout indicator in waybar";

  config = lib.mkIf (config.bjackman.bar == "waybar") {
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
          "battery"
          "keyboard-state"
        ]
        ++ lib.optionals config.bjackman.waybar.showKeyboardLayout [
          "sway/language"
        ]
        ++ [
          # We're gonna run nm-applet which should show up in the tray, but also
          # put the network module next to it since it has some nice info there.
          "network"
          "tray"
          "clock"
        ];
        "sway/language" = lib.mkIf config.bjackman.waybar.showKeyboardLayout {
          format = "{short}";
        };
        keyboard-state = {
          capslock = true;
          format = "{icon}";
          format-icons = {
            # Changing the text like this reflows the bar and it looks a bit crap.
            # I tried to fix this with CSS but it's not really properly supported.
            # Whatever.
            locked = "CAPS";
            unlocked = "caps";
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
          # Debian's font-awesome doesn't have all the individual thermometer
          # icons so just use a single icon to represent "temp".
          format-icons = [ "" ];
        };
        backlight = {
          format = "{percent}% {icon}";
          # Like with temp, use a single "brightness" icon that exists in Debian's
          # font-awesome.
          format-icons = [ "" ];
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
                <child>
                  <object class="GtkMenuItem" id="logout">
                    <property name="label">Logout</property>
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
            logout = "swaymsg exit";
          };
        };
      };
      style = pkgs.replaceVars ./waybar.css { start-icon-png = ../hm_files/common/quickshell/start.png; };
    };
  };
}
