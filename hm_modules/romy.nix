{ config, pkgs, ... }:

{
  home = {
    username = "romybinswanger";
    homeDirectory = "/Users/romybinswanger";
  };

  # Note: I was getting regular persistent backup failures due to stale locks on
  # the Restic repo. According to Claude, Restic can detect and clean up stale
  # locks but uses the combination of PID+Hostname to decide if it's safe to do
  # this, and that is unstable on MacOS. It gave me these commands to stabilise
  # it which should help to make the cleanup reliable:
  # sudo scutil --set HostName macbook-air-8
  # sudo scutil --set ComputerName macbook-air-8
  # sudo scutil --set LocalHostName macbook-air-8

  services.restic = {
    enable = true;
    backups = {
      # Most of the options here don't work on Darwin, this just creates a
      # script with the dependencies and auth set up.
      daily = {
        # Can't be bothered to couple this more neatly to the rest of the config
        # so we're just hard-coding the target hostname and "uploads" dir.
        # Note this hard-codes a different username than the local Unix one.
        repository = "sftp:romy@norte:/uploads/restic-repo";
        passwordFile = "${pkgs.writeText "restic-repo-password.txt" "hunter2"}";
      };
    };
  };

  launchd.agents.restic-backup = {
    enable = true;
    config = {
      Program =
        let
          restic-daily = "${config.home.homeDirectory}/.nix-profile/bin/restic-daily";
          script = pkgs.writeShellScript "restic-backup-daily" ''
            ${restic-daily} backup ~/Desktop ~/Documents ~/Downloads ~/Pictures
            ${restic-daily} forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
          '';
        in
        "${script}";
      StartInterval = 24 * 60 * 60;
      RunAtLoad = true;
      LowPriorityIO = true;
      ProcessType = "Background";
      # According to AI there's no equivalent of the journal on Darwin.
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/restic-daily.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/restic-daily.log";
    };
  };

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
}
