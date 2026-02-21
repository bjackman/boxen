{
  lib,
  pkgs,
  config,
  agenix,
  agenix-template,
  homelab,
  ...
}:
{
  imports = [
    agenix.nixosModules.default
    agenix-template.nixosModules.default
  ];

  options.bjackman.sambaMounts = lib.mkOption {
    type =
      with lib.types;
      attrsOf (
        submodule (
          { config, ... }:
          {
            options = {
              passwordFile = lib.mkOption {
                type = path;
                description = "Path of Age secret containing password to authenticate with";
              };
              sambaUser = lib.mkOption {
                type = attrs;
                default =
                  let
                    name = config._module.args.name;
                  in
                  homelab.servers.samba.bjackman.samba.users.${name};
                description = ''
                  Reference to the server's definition of the user in the
                  bjackman.samba.users option.
                '';
              };
              localUser = lib.mkOption {
                type = str;
                default = "root";
                description = "Local Unix user that will own the files in the mount.";
              };
              localGroup = lib.mkOption {
                type = str;
                default = "root";
                description = "Local Unix group that will own the files in the mount.";
              };
              mountpoint = lib.mkOption {
                type = str;
                description = "Local path to mount the share";
              };
            };
          }
        )
      );
  };

  config =
    let
      cfg = config.bjackman.sambaMounts;
    in
    {
      # Wiki says this is required
      environment.systemPackages = [ pkgs.cifs-utils ];

      age.secrets = lib.mapAttrs' (
        name: mountCfg: lib.nameValuePair "${name}-samba-password" { file = mountCfg.passwordFile; }
      ) cfg;

      age-template.files = lib.mapAttrs' (
        name: mountCfg:
        lib.nameValuePair "${name}-samba-creds" {
          vars.password = config.age.secrets."${name}-samba-password".path;
          content = ''
            username=${mountCfg.sambaUser.name}
            password=$password
            domain=${homelab.servers.samba.services.samba.settings.global.workgroup}
          '';
        }
      ) cfg;

      fileSystems = lib.mapAttrs' (
        name: mountCfg:
        lib.nameValuePair mountCfg.mountpoint {
          device = "//${homelab.servers.samba.networking.hostName}/${mountCfg.sambaUser.shareName}";
          fsType = "cifs";
          options = [
            "x-systemd.automount"
            "noauto"
            "credentials=${config.age-template.files."${name}-samba-creds".path}"
            "nofail"
            # Local user that owns the files mounted here
            "uid=${mountCfg.localUser}"
            "gid=${mountCfg.localGroup}"
          ];
        }
      ) cfg;
    };
}
