{ pkgs, config, ... }:
{
  home = {
    username = "jackmanb";
    homeDirectory = "/usr/local/google/home/jackmanb";

    sessionPath = [
      # I don't know why this is necessary but for some reason I don't get PATH set
      # up on gLinux.
      "${config.home.profileDirectory}/bin"
      # "Temporary hack": make stuff I've installed with "pipx" etc visible,
      # until I can migrate to a proper package manager.
      "${config.home.homeDirectory}/.local/bin"
    ];
  };

  common.fishConfigDirs = [ ../files/jackmanb/config/fish ];

  accounts.email.accounts.work = {
    address = "jackmanb@google.com";
    realName = "Brendan Jackman";
  };
  # This tells the lkml module to update the rest of the account defined above.
  lkml.accountName = "work";
}
