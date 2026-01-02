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

  options.bjackman.sftpServer.chrootsDir = lib.mkOption {
    type = lib.types.path;
    default = "/mnt/nas/sftp-chroots";
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
          ForceCommand internal-sftp
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
        "${cfg.chrootsDir}/${user.name}/uploads" = {
          d = {
            user = "${user.name}";
            group = "users";
            mode = "0700";
          };
        };
      }) (builtins.attrValues sftpUsers)
    );
  };
}
