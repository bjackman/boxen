# Defines stuff to be started alongside the Wayland session.
{
  pkgs,
  config,
  lib,
  ...
}:
{
  options = {
    bjackman.wayland-services = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Attrset of { name = cmd; }. Each item will be turned into a systemd
        service that runs the command as part of the wayland session. You'll
        need to set wayland.systemd.target for this to work.

        Also note https://github.com/nix-community/home-manager/issues/7895.
        If the target used for the wayland session doesn't actually track
        the compositor things might not get restarted as desired.
      '';
    };
  };
  # Inspired by https://github.com/nix-community/home-manager/blob/3b955f5f0a942f9f60cdc9cacb7844335d0f21c3/modules/programs/waybar.nix#L346
  # There are bits of this that are probably unnecessary or wrong, I haven't
  # looked at it much.
  config.systemd.user.services = lib.mapAttrs (
    name: cmd:
    let
      target = config.wayland.systemd.target;
    in
    {
      Unit = {
        PartOf = [
          target
          "tray.target"
        ];
        After = [ target ];
        ConditionEnvironment = "WAYLAND_DISPLAY"; # I dunno what this does lol
      };
      Service = {
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
        ExecStart = cmd;
        # Why this and not "mixed"? I dunno, Claude Opus suggested it for reasons
        # that seem meh to me. Whatever.
        KillMode = "process";
        Restart = "on-failure";
      };
      Install.WantedBy = [
        target
        "tray.target"
      ];
    }
  ) config.bjackman.wayland-services;
}
