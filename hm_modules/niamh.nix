{ config, pkgs, ... }:
{
  home = {
    username = "niamh";
    homeDirectory = "/home/niamh";
    stateVersion = "25.11";
  };

  services.restic = {
    enable = true;
    backups = {
      daily = {
        # Can't be bothered to couple this more neatly to the rest of the config
        # so we're just hard-coding the target hostname and "uploads" dir.
        repository = "sftp:${config.home.username}@norte:/uploads/restic-repo";
        paths = map (name: "${config.home.homeDirectory}/${name}") [
          "Desktop"
          "Documents"
          "Downloads"
          "Music"
          "Pictures"
          "Videos"
        ];
        passwordFile = "${pkgs.writeText "restic-repo-password.txt" "hunter2"}";
        # The repo already exists (initialized manually with
        # `restic -r sftp:niamh@norte:/uploads/restic-repo init`), so leave this
        # off. With it on, the pre-start `restic cat config || restic init` turns
        # any transient repo-open failure (e.g. a stale lock or network blip)
        # into an `init` attempt that dies with the confusing "config file
        # already exists". Off means such failures fail honestly instead.
        initialize = false;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
        ];
      };
    };
  };

  programs.home-manager.enable = true;
}
