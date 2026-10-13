{
  pkgs,
  lib,
  config,
  ...
}:
let
  users = lib.filterAttrs (name: user: user.enableSftp) config.bjackman.homelab.users;
  chrootsDir = config.bjackman.sftpServer.chrootsDir;
  serviceName = userName: "restic-exporter-${userName}";
in
{
  imports = [
    ./sftp-server.nix
    ../ports.nix
  ];

  # This is a bit hacky, we're assuming that all the users that have SFTP access
  # enabled have a Restic repository, and then we're assuming that they always
  # put their Restic repo in the same subdir of the chroot, also that they all
  # use the same password.
  bjackman.restic-exporter.instances = lib.mapAttrs (_: user: {
    repositoryPath = "${chrootsDir}/${user.name}/uploads/restic-repo";
    port = config.bjackman.ports.${serviceName user.name}.port;
    passwordFile = "${pkgs.writeText "restic-repo-password.txt" "hunter2"}";
    listenAddress = "0.0.0.0";
  }) users;

  bjackman.ports = lib.mapAttrs' (name: _: lib.nameValuePair (serviceName name) { }) users;

  users.groups.restic-readers = { };
  bjackman.restic-exporter.group = "restic-readers";
  bjackman.sftpServer.extraReaders = [ "restic-readers" ];

  # A client that dies mid-run leaves its lock behind and restic never clears
  # it by itself, so an interrupted prune blocks every later backup.
  systemd.services = lib.mapAttrs' (
    name: user:
    let
      instance = config.bjackman.restic-exporter.instances.${name};
    in
    lib.nameValuePair "restic-unlock-${name}" {
      startAt = "hourly";
      unitConfig.RequiresMountsFor = [ chrootsDir ];
      environment = {
        RESTIC_REPOSITORY = instance.repositoryPath;
        RESTIC_PASSWORD_FILE = instance.passwordFile;
      };
      serviceConfig = {
        Type = "oneshot";
        User = user.name;
        ExecStart = "${pkgs.restic}/bin/restic unlock --no-cache";
      };
    }
  ) users;
}
