# https://github.com/ngosang/restic-exporter has configuration in NixOS but it
# only supports exporting data from a single Restic repo per instance, the
# intended model is to just run multiple instances:
# https://github.com/ngosang/restic-exporter/issues/26#issuecomment-1915364225
# The NixOS config is using a general framework for prometheus exporters so it
# isn't really amenable to being adapted to run multiple instances. So here's a
# custom setup instead.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  options.bjackman.restic-exporter = {
    # Just use one user for all instances for lazy simplicity.
    user = lib.mkOption {
      type = lib.types.str;
      default = "restic-exporter";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "restic-exporter";
    };
    instances = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          submodule (
            { config, ... }:
            {
              options = {
                name = lib.mkOption {
                  type = str;
                  default = config._module.args.name;
                  description = "Name of the instance";
                };
                repositoryPath = lib.mkOption {
                  type = with lib.types; nullOr str;
                  default = null;
                  description = ''
                    File path of repository.

                    To make this work with other repository URI types than a raw
                    local file path, the systemd confinement will need tweaking.
                  '';
                  example = "/backups/example";
                };
                port = lib.mkOption {
                  type = int;
                  default = 9753;
                  description = "HTTP port to listen on";
                };
                listenAddress = lib.mkOption {
                  type = str;
                  default = "127.0.0.1";
                };
                passwordFile = lib.mkOption {
                  type = str;
                  description = "File containing repository password";
                };
                refreshIntervalSecs = lib.mkOption {
                  type = int;
                  description = "Refresh interval for scraping the repo";
                  default = 60 * 60;
                };
              };
            }
          )
        );
    };
  };

  config.systemd.services =
    let
      cfg = config.bjackman.restic-exporter;
      mkService = instance: {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Restart = "always";
          DynamicUser = true;
          User = cfg.user;
          Group = cfg.group;
          BindReadOnlyPaths = [
            instance.passwordFile
            instance.repositoryPath
          ];
        };
        confinement.enable = true;
        environment = {
          RESTIC_REPOSITORY = instance.repositoryPath;
          RESTIC_PASSWORD_FILE = instance.passwordFile;
          LISTEN_ADDRESS = instance.listenAddress;
          LISTEN_PORT = toString instance.port;
          REFRESH_INTERVAL = toString instance.refreshIntervalSecs;
        };
        script = ''
          export RESTIC_CACHE_DIR="$CACHE_DIRECTORY"
          ${pkgs.prometheus-restic-exporter}/bin/restic-exporter.py
        '';
      };
    in
    lib.mapAttrs' (_: instance: {
      name = "prometheus-restic-exporter-${instance.name}";
      value = mkService instance;
    }) cfg.instances;
}
