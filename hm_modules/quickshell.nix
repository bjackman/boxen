{
  pkgs,
  config,
  lib,
  ...
}:
{
  config = lib.mkIf (config.bjackman.bar == "quickshell") {
    programs.quickshell = {
      enable = true;
      package = pkgs.quickshell;
      configs.bjackman = ../hm_files/common/quickshell;
      activeConfig = "bjackman";
      systemd = {
        enable = true;
        target = config.wayland.systemd.target;
      };
    };
  };
}
