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

    # The upstream module's unit isn't PartOf the session target, so it
    # outlives the compositor. Same problem the waybar module has:
    # https://github.com/nix-community/home-manager/issues/7895
    systemd.user.services.quickshell.Unit.PartOf = [ config.wayland.systemd.target ];
  };
}
