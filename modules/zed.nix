{
  config,
  ...
}:
{
  # We don't set programs.zed-editor.enable here, this module is just
  # configuring it, we leave it up to other modules to install it. This is
  # because some of these configurations are used on non-NixOS systems where
  # it's easier to just install it from Flatpak.

  # So that we can edit the settings via Zed's nice settings editor, we just
  # check in the raw files and link to them. This means that a) the
  # configuration is separated from the home-manager config lifecycle (fine?)
  # and b) we have to write yucky JSON if we want to edit them by hand (which...
  # hopefullyt we don't?).
  xdg.configFile = {
    "zed/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.config-checkout}/files/common/config/zed/settings.json";
    };
    "zed/keymap.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.config-checkout}/files/common/config/zed/keymap.json";
    };
  };
  # Link the global config directory into the flatpak's local config
  # directory.
  home.file.".var/app/dev.zed.Zed/config/zed" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/zed";
  };
}
