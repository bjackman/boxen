{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.bjackman.nix-warmups = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
    description = "" "List of flake references to keep warm.

    Creates a systemd service that regularly builds these references and puts
    the result into a gcroot.
    " "";
    example = [ "github:bjackman/limmat-kernel-nix/master#devShells.x86_64-linux.kernel" ];
  };

  config =
    let
      # Helper: "github:user/repo#attr" -> "github-user-repo-attr"
      # Creates a safe string for filenames and systemd unit names
      escapeRef = flakeRef: builtins.replaceStrings [ ":" "/" "#" "@" ] [ "-" "-" "-" "-" ] flakeRef;

      mkService = flakeRef: {
        name = "nix-warmup-${escapeRef flakeRef}";
        value = {
          Unit.Description = "Warm up nix build for ${flakeRef}";
          Service = {
            Type = "oneshot";
            CacheDirectory = "nix-warmups";
            # --refresh means to pull from the remote.
            # --out-link overrides what would normally be ./result. This is what
            # creates the GC root.
            ExecStart = pkgs.writeShellScript "warmup-${escapeRef flakeRef}-script" ''
              set -euo pipefail
              ${pkgs.nix}/bin/nix build "${flakeRef}" --refresh \
                --out-link "$CACHE_DIRECTORY/${escapeRef flakeRef}"
            '';
          };
        };
      };

      mkTimer = flakeRef: {
        name = "nix-warmup-${escapeRef flakeRef}";
        value = {
          Unit.Description = "Timer for ${flakeRef} nix warmup";
          Timer = {
            OnUnitActiveSec = "1h";
            OnBootSec = "5m";
            RandomizedDelaySec = "300";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

      flakeRefs = config.bjackman.nix-warmups;
    in
    lib.mkIf (flakeRefs != [ ]) {
      systemd.user.services = lib.listToAttrs (map mkService flakeRefs);
      systemd.user.timers = lib.listToAttrs (map mkTimer flakeRefs);
    };
}
