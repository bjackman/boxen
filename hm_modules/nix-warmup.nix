{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.bjackman.nix-warmups = lib.mkOption {
    type =
      with lib.types;
      let
        submodType = submodule {
          options = {
            flakeRef = lib.mkOption {
              type = str;
              description = "Flake reference to build";
            };
            buildArgs = lib.mkOption {
              type = listOf str;
              default = [ ];
              description = "Extra args for nix build";
            };
          };
        };
      in
      listOf (coercedTo str (flakeRef: { inherit flakeRef; }) submodType);
    default = [ ];
    description = ''
      List of flake references to keep warm.

      Creates a systemd service that regularly builds these references and puts
      the result into a gcroot.
    '';
  };

  config =
    let
      # Helper: "github:user/repo#attr" -> "github-user-repo-attr"
      # Creates a safe string for filenames and systemd unit names
      escapeRef = flakeRef: builtins.replaceStrings [ ":" "/" "#" "@" ] [ "-" "-" "-" "-" ] flakeRef;

      # Don't run on "metered network", in practice this is about being tethered
      # to a phone hotspot. Claude says that Android sets magic options in its
      # AP or DHCP or something that NetworkManager is able to use to detect the
      # tether.
      unmetered = pkgs.writeShellScript "unmetered" ''
        # NMMetered: 1=yes 2=no 3=guess-yes 4=guess-no 0=unknown
        m=$(${pkgs.systemd}/bin/busctl --system get-property org.freedesktop.NetworkManager \
              /org/freedesktop/NetworkManager \
              org.freedesktop.NetworkManager Metered)
        # Anything else, including busctl failing on hosts with no NetworkManager,
        # leaves $m empty and we go ahead.
        case "''${m##* }" in 1 | 3) exit 1 ;; *) exit 0 ;; esac
      '';

      mkService =
        { flakeRef, buildArgs }:
        {
          name = "nix-warmup-${escapeRef flakeRef}";
          value = {
            Unit = {
              Description = "Warm up nix build for ${flakeRef}";
              ConditionACPower = true;
            };
            Service = {
              Type = "oneshot";
              CacheDirectory = "nix-warmups";
              ExecCondition = unmetered;
              # --refresh means to pull from the remote.
              # --out-link overrides what would normally be ./result. This is what
              # creates the GC root.
              ExecStart = pkgs.writeShellScript "warmup-${escapeRef flakeRef}-script" ''
                set -euo pipefail
                ${pkgs.nix}/bin/nix build ${lib.concatStringsSep " " buildArgs} "${flakeRef}" --refresh \
                  --out-link "$CACHE_DIRECTORY/${escapeRef flakeRef}"
              '';
            };
          };
        };

      mkTimer =
        { flakeRef, ... }:
        {
          name = "nix-warmup-${escapeRef flakeRef}";
          value = {
            Unit.Description = "Timer for ${flakeRef} nix warmup";
            Timer = {
              OnUnitActiveSec = "1h";
              OnStartupSec = "5m";
              RandomizedDelaySec = "300";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };

      warmups = config.bjackman.nix-warmups;
    in
    lib.mkIf (warmups != [ ]) {
      systemd.user.services = lib.listToAttrs (map mkService warmups);
      systemd.user.timers = lib.listToAttrs (map mkTimer warmups);
    };
}
