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

  # Required by Zed.
  nixGL.vulkan.enable = true;
  programs.zed-editor = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.zed-editor;
  };

  common.fishConfigDirs = [ ../files/jackmanb/config/fish ];

  accounts.email.accounts.work = {
    address = "jackmanb@google.com";
    realName = "Brendan Jackman";
    # TODO: This really badly needs to be configured in lkml.nix instead.
    notmuch.enable = true;
    aerc = {
      enable = true;
      extraAccounts =
        # This configures the "folders", i.e. the things in the side bar, by
        # mapping them to notmuch queries.
        let
          queryMap = pkgs.writeText "query-map.conf" ''
            Inbox=not tag:archived and not tag:thread-muted
            All=true
          '';
        in
        {
          source = "notmuch://${config.lkml.maildirBasePath}";
          # Needed for postponing messages:
          #  https://lists.sr.ht/~rjarry/aerc-discuss/%3CD931B2ZI6UH5.1L6FTH0TGJIQO@google.com%3E
          maildir-store = "${config.lkml.maildirBasePath}";
          query-map = "${queryMap}";
          outgoing = "/usr/bin/sendgmr -i";
        };
    };
    primary = true;
  };
  lkml.enable = true;
}
