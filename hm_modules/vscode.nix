{
  config,
  ...
}:
{
  programs.vscode.enable = true;
  xdg.configFile = {
    "Code/User/settings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.common.config-checkout}/hm_files/common/config/Code/User/settings.json";
    };
  };
  xdg.configFile = {
    "Code/User/keybindings.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.common.config-checkout}/hm_files/common/config/Code/User/keybindings.json";
    };
  };
}
