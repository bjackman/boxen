{
  config,
  options,
  pkgs,
  lib,
  impermanence,
  agenix,
  ...
}:
{
  imports = [
    impermanence.nixosModules.impermanence
    agenix.nixosModules.default
  ];

  # The raw impermanence module is quite low-level and requires everything that
  # interacts with it to explicitly specify the mountpoint of the persistent
  # data that it's referring to. These options make that higher level, to do
  # this we assume that there is exactly one such mountpoint. Then, other bits
  # of configuration don't need to care about it they just say "persist this
  # shit".
  options.bjackman.impermanence = {
    enable = lib.mkEnableOption "impermanence";
    extraPersistence = lib.mkOption {
      default = { };
      # Without this type I got confusing merging behaviour. I had two modules
      # setting the option and instead of merging them, Nix had one version
      # override the other. Gemini claims this is because if one module imports
      # another, it overrides its options instead of merging with them. I don't
      # know if that's true. Anyway, it gave me this fancy business which is
      # probably for the best anyway.
      type = lib.types.submodule {
        options = {
          directories = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [ ];
          };
          users = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  files = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                  directories = lib.mkOption {
                    type = lib.types.listOf lib.types.anything;
                    default = [ ];
                  };
                };
              }
            );
            default = { };
          };
        };
      };
      description = ''
        Overlay to apply to
        environment.persistence."${config.bjackman.impermanence.persistentMountPoint}"
      '';
    };
  };

  config =
    let
      cfg = config.bjackman.impermanence;
    in
    lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.fileSystems ? "/persistent";
          message = ''fileSystems."/persistent" must be defined for this module to work'';
        }
      ];

      environment.persistence."/persistent" = lib.mkMerge [
        # Define a base config here with basic shit that most machines are gonna
        # want persisted. Then for application-specific persistence that wil be
        # set elsewhere next to the configuration of that app.
        {
          hideMounts = true; # Don't spam all these mounts in file managers.
          directories = [
            "/var/log"
            "/var/lib/bluetooth" # Apparently bluetooth pairing is system-global.
            "/var/lib/nixos" # Needed for consistent UIDs
            "/var/lib/systemd/coredump"
            "/etc/NetworkManager/system-connections"
            "/var/lib/AccountsService" # Used by GDM to remember last choice of desktop.
            "/var/lib/systemd/timers" # Ensure we don't forget persistent timer state.
            "/var/lib/tailscale"
          ];
          files = [
            "/etc/machine-id"
            "/etc/ssh/ssh_host_ed25519_key"
            "/etc/ssh/ssh_host_ed25519_key.pub"
            "/etc/ssh/ssh_host_rsa_key"
            "/etc/ssh/ssh_host_rsa_key.pub"
          ];
        }
        cfg.extraPersistence
      ];
    };
}
