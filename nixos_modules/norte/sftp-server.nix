{
  config,
  lib,
  pkgs,
  ...
}:
let
  sftpUsers = lib.filterAttrs (n: u: u.enableSftp) config.bjackman.homelab.users;
  cfg = config.bjackman.sftpServer;
in
{
  imports = [
    ../users.nix
  ];

  options.bjackman.sftpServer = {
    chrootsDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/nas/sftp-chroots";
    };
    extraReaders = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Groups to add to the Posix ACL for read access to the contents of the
        SFTP chroot dirs.
      '';
    };
  };

  config = {
    users.groups.sftp-only = { };
    users.users = lib.mapAttrs (name: user: {
      isNormalUser = true;
      group = "sftp-only";
      description = user.displayName;
      createHome = false;
      openssh.authorizedKeys.keys = [ user.publicKey ];
    }) sftpUsers;

    services.openssh = {
      enable = true;
      extraConfig = ''
        Match Group sftp-only
          # Hm it's too late for me to try and understand this. AI says:
          # -u 0022 ensures files are created with at least 644 and dirs 755, 
          # allowing the Default ACL to apply its 'rx' bits.
          # Apparently this will allow the recursive default Posix ACL set in
          # the extraReaders option to take effect.
          ForceCommand internal-sftp -u 0022
          # Chroot to their specific SFTP directory. OpenSSH requires that the
          # chroot is owned by root so we can't really use the normal users
          # directory here unfortunately.
          ChrootDirectory ${cfg.chrootsDir}/%u
          AllowTcpForwarding no
          AllowAgentForwarding no
          X11Forwarding no
      '';
    };

    systemd.tmpfiles.settings."10-mnt-nas-sftp-chroots" = lib.mkMerge (
      map (user: {
        "${cfg.chrootsDir}/${user.name}" = {
          d = {
            user = "root";
            group = "root";
            mode = "0755";
          };
        };
        # This subdirectory exists to be writable by the user.
        # Note the name of this directory is implicitly coupled with the client
        # configurations.
        "${cfg.chrootsDir}/${user.name}/uploads" = {
          d = {
            user = "${user.name}";
            group = "users";
            mode = "0710";
          };
        };
      }) (builtins.attrValues sftpUsers)
    );

    # Grant the extra reader accesses to the contents of the SFTP chroots. This
    # is done as a separate block that comes "after" the main chroot definitions
    # because AI told me I should do this while troubleshooting, I suspect this
    # was bullshit but I haven't tried merging them again.
    # The real issue was that the target FS (ZFS) didn't have Posix ACLs enabled
    # - I fixed this on the CLI (it's a property of the ZFS dataset) with
    # sudo zfs set  acltype=posixacl nas.
    systemd.tmpfiles.settings."20-sftp-readers" = lib.mkMerge (
      map (user: {
        "${cfg.chrootsDir}/${user.name}/uploads" = {
          # Set up Posix ACLs so that these other groups get access to read the
          # contents of the directory.
          "a+".argument = lib.concatStringsSep "," (
            # This grants access to the directory itself.
            (map (group: "group:${group}:rx") cfg.extraReaders)
            ++
              # This sets up the umask so that files created in the directory are
              # accessible.
              (map (group: "default:group:${group}:rx") cfg.extraReaders)
          );
        };
      }) (builtins.attrValues sftpUsers)
    );
  };
}
