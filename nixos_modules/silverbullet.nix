{ pkgs, config, ... }:
{
  imports = [
    ./ports.nix
    ./iap.nix
  ];

  bjackman.ports.silverbullet = { };

  bjackman.iap.services.silverbullet = {
    port = config.bjackman.ports.silverbullet.port;
    allowedUsers = [ "brendan" ];
  };

  services.silverbullet = {
    enable = true;
    openFirewall = true;
    listenPort = config.bjackman.ports.silverbullet.port;
  };

  # I had a hard time deciding how to set up the backup system. Could use plain
  # rsync, could use samba, could use Git. In the end I kinda just picked Restic
  # arbitrarily.
  age.secrets.brendan-sftp-privkey = {
    file = ../secrets/brendan-sftp-privkey.age;
    mode = "400";
  };
  services.restic.backups.silverbullet = {
    repository = "sftp:brendan-sftp@norte:/uploads/restic-silverbullet";
    initialize = true;
    paths = [ config.services.silverbullet.spaceDir ];
    passwordFile = "${pkgs.writeText "restic-repo-password.txt" "hunter2"}";
    extraOptions =
      let
        key = config.age.secrets.brendan-sftp-privkey.path;
      in
      [
        "sftp.command='ssh brendan-sftp@norte -i ${key} -o StrictHostKeyChecking=no -s sftp'"
      ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    pruneOpts = [
      "--keep-hourly 24"
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };
}
