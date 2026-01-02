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
            };
          }
        )
      );
    default = with config.age.secrets; {
      filebrowser.passwordFile = filebrowser-samba-password.path;
      romy.passwordFile = romy-samba-password.path;
    };
  };

  config =
    let
      cfg = config.bjackman.samba;
      timeMachineShareName = "romy_time_machine";
    in
    {
      age.secrets = {
        filebrowser-samba-password.file = ../../secrets/filebrowser-samba-password.age;
        romy-samba-password.file = ../../secrets/romy-samba-password.age;
      };
      systemd.tmpfiles.settings."10-mnt-nas-samba" = {
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

            # # Use modern I/O
            # "use sendfile" = "yes";
            # "aio read size" = "1";
            # "aio write size" = "1";

            # LAN and localhost access only
            # TODO also adding a temporary IPv6 from romy's macbook while I
            # figure other stuff out.
            "hosts allow" = "192.168. 100. 127. fe80:: ::1 2a02:168:f7b6:0:4118:24ca:acf2:8c8b";
            "hosts deny" = "0.0.0.0/0 ::/0";

            # I have no idea WTF this is but I was seeing errors in smbd's log
            # about "parse_dfs_path_strict" and AI told me I can make it go away
            # by disabling this feature I probably don't need:
            "host msdfs" = "no";
            # More unknown AI stuff:
            "ea support" = "yes";
            "vfs objects" = "catia fruit streams_xattr"; # Ensure this is in Global AND the
            # https://reifschneider.digital/blog/ultimate-guide-samba-time-machine-backups?lang=en
            "wide links" = "yes";
            "unix extensions" = "no";
            "vfs object" = "acl_xattr catia fruit streams_xattr";
            "fruit:nfc_aces" = "no";
            "fruit:aapl" = "yes";
            "fruit:model" = "MacSamba";
            "fruit:posix_rename" = "yes";
            "fruit:metadata" = "stream";
            "fruit:delete_empty_adfiles" = "yes";
            "fruit:veto_appledouble" = "no";
            "spotlight" = "yes";
            # https://blog.jhnr.ch/2023/01/09/setup-apple-time-machine-network-drive-with-samba-on-ubuntu-22.04/
            "fruit:copyfile" = "no";
            # Don't clash with Avahi
            "multicast dns register" = "no";
            "client max protocol" = "default";
            "client min protocol" = "SMB2_02";
            "server max protocol" = "SMB3";
            "server min protocol" = "SMB2_02";
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
          ${timeMachineShareName} = {
            "path" = "/mnt/nas/romy_time_machine";
            "valid users" = cfg.users.romy.name;
            "force user" = cfg.users.romy.name;
            "public" = "no";
            "guest ok" = "no";
            "writeable" = "yes";
            # Below are the most imporant for macOS compatibility
            # Change the above to suit your needs
            "fruit:aapl" = "yes";
            "fruit:time machine" = "yes";
            "vfs objects" = "catia fruit streams_xattr";
            # Suggested by AI to deal with timer machine creating .incomplete
            # backups and failing:
            "fruit:metadata" = "stream";          # Better for sparsebundles
            "fruit:nfs_aces" = "no";      # Prevents macOS from trying to use NFS ACLs on SMB
            "fruit:posix_rename" = "yes"; # Helps with the .incomplete folder rename logic
            # https://reifschneider.digital/blog/ultimate-guide-samba-time-machine-backups?lang=en
            "available" = "yes";
            "fruit:time machine max size" = "1T";
          };
        };
      };
      systemd.tmpfiles.settings."10-mnt-nas-samba" = {
        "/mnt/nas/romy_time_machine".d = {
          group = "samba";
          mode = "0700";
          user = cfg.users.romy.name;
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

      services.avahi = {
        publish.enable = true;
        # Comments from https://wiki.nixos.org/wiki/Samba
        # Needed to allow samba to automatically register mDNS records
        # (without the need for an `extraServiceFile`
        publish.userServices = true;
        # Not one hundred percent sure if this is needed.
        nssmdns4 = true;
        enable = true;
        openFirewall = true;
        extraServiceFiles = {
          timemachine = ''
            <?xml version="1.0" standalone='no'?>
            <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
            <service-group>
              <name replace-wildcards="yes">%h</name>
              <service>
                <type>_smb._tcp</type>
                <port>445</port>
              </service>
                <service>
                <type>_device-info._tcp</type>
                <port>0</port>
                <txt-record>model=TimeCapsule8,119</txt-record>
              </service>
              <service>
                <type>_adisk._tcp</type>
                <txt-record>dk0=adVN=${timeMachineShareName},adVF=0x82</txt-record>
                <txt-record>sys=waMa=0,adVF=0x100</txt-record>
              </service>
            </service-group>
          '';
        };
      };
      # This is in the wiki, I have no idea if it's actually relevant. But it's
      # useful anyway.
      networking.firewall.allowPing = true;
    };
}
