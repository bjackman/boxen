{
  pkgs,
  config,
  lib,
  agenix,
  ...
}:
{
  imports = [
    agenix.nixosModules.default
  ];

  options.bjackman.samba.users = lib.mkOption {
    type =
      with lib.types;
      attrsOf (
        submodule (
          let
            fullConfig = config;
          in
          { config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = str;
                default = "samba-${config._module.args.name}";
                description = "Name of user. This defines a Unix user as well as a Samba one so call it samba-*";
              };
              passwordFile = lib.mkOption {
                type = path;
                description = "File containing users Samba password. (Not unix password)";
              };
              shareName = lib.mkOption {
                type = str;
                description = ''
                  Share for this user. Each user gets its own share that it has
                  access to, this identifies the one for thi user.
                '';
              };
              shareDevice = lib.mkOption {
                type = str;
                readOnly = true;
                default = "//${fullConfig.networking.hostName}/${config.shareName}";
                description = ''
                  Assuming you're on the same LAN as the server, this is what
                  you put in the `device` field of the fileSystems option to
                  mount the share on the CIFS client.
                '';
              };
            };
          }
        )
      );
    default = {
      filebrowser = {
        passwordFile = config.age.secrets.filebrowser-samba-password.path;
        # Note this user is magic as it can access the "nas" share which means it
        # can read and write the entire NAS.
        shareName = "nas";
      };
    };
  };

  config =
    let
      cfg = config.bjackman.samba;
    in
    {
      age.secrets.filebrowser-samba-password.file = ../../secrets/filebrowser-samba-password.age;
      systemd.tmpfiles.settings."10-mypackage" = {
        "/mnt/nas" = {
          d = {
            group = "samba";
            mode = "0755";
            user = "root";
          };
        };
      };
      services.samba = {
        enable = true;
        openFirewall = true;
        settings = {
          global = {
            "workgroup" = "WORKGROUP";
            "security" = "user";

            # Use modern I/O
            "use sendfile" = "yes";
            "aio read size" = "1";
            "aio write size" = "1";

            # Use modern protocol
            "server min protocol" = "SMB3_11";

            # LAN and localhost access only
            "hosts allow" = "192.168. 100. 127. fe80:: ::1";
            "hosts deny" = "0.0.0.0/0 ::/0";
          };
          "nas" = {
            "path" = "/mnt/nas";
            "browseable" = "yes";
            "read only" = "no";
            "guest ok" = "no";
            "create mask" = "0644";
            "directory mask" = "0755";
            "force user" = "samba";
            "force group" = "samba";
            "valid users" = cfg.users.filebrowser.name;
          };
        };
      };
      users.users =
        # Samba users need to correspond to Unix users, create those. IIUC these
        # aren't used for any ACL checks they just need to exists for some reason
        # I don't care about.
        (lib.mapAttrs' (attrName: user: {
          name = user.name;
          value = {
            isSystemUser = true;
            group = "samba";
          };
        }) cfg.users)
        // {
          # The actual ACL checks are done via this general user. Note this
          # _isn't_ used to actually run a daemon, Samba runs as root.
          samba = {
            isSystemUser = true;
            group = "samba";
            description = "Samba filesystem access user";
          };
        };
      users.groups.samba = { };
      # Create samba users.
      system.activationScripts = lib.mapAttrs' (name: user: {
        name = "smbpasswd-${name}";
        value = {
          deps = [
            "agenix"
            "users"
            "groups"
          ];
          text =
            let
              smbpasswd = "${pkgs.samba}/bin/smbpasswd";
              pdbedit = "${pkgs.samba}/bin/pdbedit";
            in
            ''
              password=$(cat ${user.passwordFile})
              # Add new user if it doesn't exist. Otherwise update password.
              # Need to write the password twice as smbpasswd requires confirmation
              # even non-interactive mode.
              if ! ${pdbedit} -u ${user.name} > /dev/null 2>&1; then
                printf "$password\n$password\n" | ${smbpasswd} -s -a ${user.name}
              else
                printf "$password\n$password\n" | ${smbpasswd} -s ${user.name}
              fi
            '';
        };
      }) cfg.users;
    };
}
