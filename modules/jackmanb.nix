{ config, ... }:
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
    # TODO: It would be better to enable notmuch and aerc in lkml.nix as their
    # configs are all interwingled in this setup.
    notmuch.enable = true;
    aerc = {
      enable = true;
      extraAccounts = {
        source = "notmuch://${config.lkml.maildirBasePath}";
        # Needed for postponing messages:
        #  https://lists.sr.ht/~rjarry/aerc-discuss/%3CD931B2ZI6UH5.1L6FTH0TGJIQO@google.com%3E
        maildir-store = "${config.lkml.maildirBasePath}";
      };
    };
    primary = true;
    lkml.enable = true;
  };
}
