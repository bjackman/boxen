{
  config,
  lib,
  pkgs,
  jellarr,
  agenix,
  ...
}:
{
  # Note this is just the generic parts of the config, individual machines will
  # need more specific configs.
  imports = [
    agenix.nixosModules.default
    jellarr.nixosModules.default
    ./impermanence.nix
  ];

  options.bjackman.jellyfin.httpPort = lib.mkOption {
    type = lib.types.int;
    # Note if you change this then services.jellyfin.openFirewall won't work any
    # more.
    default = 8096;
  };

  config = {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    age.secrets.jellyfin-admin-password = {
      file = ../secrets/jellyfin-admin-password.age;
      mode = "440";
      group = "jellyfin";
    };
    age.secrets.jellarr-api-key.file = ../secrets/jellarr-api-key.age;
    age.secrets.jellarr-env.file = ../secrets/jellarr-env.age;
    services.jellarr = {
      enable = true;
      user = "jellyfin";
      group = "jellyfin";
      environmentFile = config.age.secrets.jellarr-env.path;
      bootstrap = {
        enable = true;
        apiKeyFile = config.age.secrets.jellarr-api-key.path;
      };
      config = {
        version = 1;
        base_url = "http://localhost:${builtins.toString config.bjackman.jellyfin.httpPort}";
        system.enableMetrics = true;
        startup.completeStartupWizard = true;
        users = [
          {
            name = "brendan";
            passwordFile = config.age.secrets.jellyfin-admin-password.path;
            policy.isAdministrator = true;
          }
        ];
      };
    };

    # Ugh, after all the effort of switching to BTRFS I realised that you can't
    # really have a fully impermanent Jellyfin setup. The whole system is just too
    # stateful. Just persist that shit.
    bjackman.impermanence.extraPersistence.directories = [
      {
        directory = "/var/lib/jellyfin";
        mode = "0770";
        group = "jellyfin";
      }
    ];
  };
}
