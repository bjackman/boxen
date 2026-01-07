{
  pkgs,
  config,
  lib,
  ...
}:
{
  options.bjackman.wezterm.extraConfig = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = ''
      Some Lua code that will be injected at the end of the base config.
      A Wezterm config_builder object will be in the "config" variable".
    '';
  };

  config.programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require 'wezterm'

      -- This seems dumb but actually it gives you better error messages and
      -- stuff. This weird imperative style is also kinda paradoxically easier
      -- to modularise.
      config = wezterm.config_builder()

      config.font_size = 11

      config.hide_tab_bar_if_only_one_tab = true

      -- https://github.com/wezterm/wezterm/issues/695#issuecomment-820160764
      config.adjust_window_size_when_changing_font_size = false

      config.scrollback_lines = 10000

        -- Disable wezterm's shortcuts since I use these keys to control Aerc.
      config.keys = {
        {
            key = 'PageUp',
            mods = 'CTRL',
            action = wezterm.action.DisableDefaultAssignment
        },
        {
            key = 'PageDown',
            mods = 'CTRL',
            action = wezterm.action.DisableDefaultAssignment
        },
      }

      -- begin bjackman.wezterm.extraConfig
      ${config.bjackman.wezterm.extraConfig}
      -- end bjackman.wezterm.extraConfig

      return config
    '';
  };
}
