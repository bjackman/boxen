{ pkgs, config, ... }:
{
  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require 'wezterm'
      return {
        font_size = 11,

        hide_tab_bar_if_only_one_tab = true,

        -- https://github.com/wezterm/wezterm/issues/695#issuecomment-820160764
        adjust_window_size_when_changing_font_size = false,

        scrollback_lines = 10000,

        -- Disable wezterm's shortcuts since I use these keys to control Aerc.
        keys = {
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
        },
      }
    '';
  };
}
