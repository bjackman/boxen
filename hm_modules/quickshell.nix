{
  pkgs,
  config,
  lib,
  ...
}:
let
  # The helpers the config shells out to are only needed by quickshell, so
  # bake their paths in rather than putting them on the user's PATH.
  configDir = pkgs.runCommand "quickshell-config" { } ''
    cp -r ${../hm_files/common/quickshell} $out
    chmod -R u+w $out
    substituteInPlace $out/Paths.qml \
      --replace-fail '"capslock-watch"' \
        '"${pkgs.bjackman.capslock-watch}/bin/capslock-watch"'
  '';
in
{
  config = lib.mkIf (config.bjackman.bar == "quickshell") {
    programs.quickshell = {
      enable = true;
      package = pkgs.quickshell;
      configs.bjackman = configDir;
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
