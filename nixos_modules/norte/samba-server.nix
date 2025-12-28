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

  options.bjackman.samba.users.filebrowser = lib.mkOption {
    type = lib.types.str;
    default = "samba-filebrowser";
  };

  config = {
    users = {
      # This user doesn't actually run the daemon it's just use for fileystem
      # ACL checks.
      users.samba = {
        isSystemUser = true;
        group = "samba";
        description = "Samba filesystem access user";
      };
      groups.samba = { };
    };
    systemd.tmpfiles.settings."10-mypackage" = {
      "/mnt/nas" = {
        d = {
          group = "samba";
          mode = "0775";
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

          # LAN access only
          "hosts allow" = "192.168. 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
        };
        # There's no "valid users" key here which means this is accessible to any
        # authenticated user.
        "nas" = {
          "path" = "/mnt/nas";
          "browseable" = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
          "force user" = "samba";
          "force group" = "samba";
        };
      };
    };
    # Samba users need to correspond to Unix users.
    users.users.${config.bjackman.samba.users.filebrowser} = {
      isSystemUser = true;
      group = "samba";
    };
    age.secrets.filebrowser-samba-password.file = ../../secrets/filebrowser-samba-password.age;
    # Create samba user for filebrowser.
    system.activationScripts.smbpasswd = {
      deps = [
        "agenix"
        "users"
        "groups"
      ];
      text =
        let
          smbpasswd = "${pkgs.samba}/bin/smbpasswd";
          pdbedit = "${pkgs.samba}/bin/pdbedit";
          passwordFile = config.age.secrets.filebrowser-samba-password.path;
          user = config.bjackman.samba.users.filebrowser;
        in
        ''
          password=$(cat ${passwordFile})
          # Add new user if it doesn't exist. Otherwise update password.
          # Need to write the password twice as smbpasswd requires confirmation
          # even non-interactive mode.
          if ! ${pdbedit} -u ${user} > /dev/null 2>&1; then
            printf "$password\n$password\n" | ${smbpasswd} -s -a ${user}
          else
            printf "$password\n$password\n" | ${smbpasswd} -s ${user}
          fi
        '';
    };
  };
}
