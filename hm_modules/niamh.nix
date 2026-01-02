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
        # Note I have not actually tested if this works, I did it manually
        # with `restic -r sftp:niamh@norte:/uploads/restic-repo init`
        initialize = true;
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
