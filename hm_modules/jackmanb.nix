{ pkgs, config, ... }:
{
  imports = [
    ./common.nix
    ./non-nixos.nix
  ];

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

    # Lol, workaround old Nix version with no support for inputs.self.submodules
    # flake attribute.
    packages = [ pkgs.nix ];
  };

  bjackman.appConfigDirs = {
    fish = [ ../hm_files/jackmanb/config/fish ];
  };

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

  programs.git =
    let
      emailAccount = config.accounts.email.accounts.work;
    in
    {
      userEmail = emailAccount.address;
      userName = emailAccount.realName;
      extraConfig = {
        # To be honest I'm not 100% sure exactly what this does.
        url."sso://user".insteadOf = "https://user.git.corp.google.com";
        # Use the gLinux SSH since the Nix one doesn't know about Google
        # weirdness.
        core.sshCommand = "/usr/bin/ssh";
      };
    };

  # There is some confusing mess with different versions of tmux doing different
  # things in different environments (login vs non login shell). Part of this
  # may or may not be related to programs.tmux.secureSocket but I still get
  # issues even if I never set TMUX_TMPDIR.
  # Hack to just set TMUX_TMPDIR everywhere, even in non-interactive shells:
  programs.bash.bashrcExtra = ''
    export TMUX_TMPDIR="$XDG_RUNTIME_DIR"
  '';

  programs.ssh = {
    enable = true;
    package = null; # Don't install (this is the default, but make sure)
    controlMaster = "auto";
    controlPersist = "8h";
    forwardAgent = true; # For gnubby
    matchBlocks."bj".hostname = "bj.c.googlers.com";
  };

  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local wezterm = require 'wezterm'
      return {
        font_size = 11,

        hide_tab_bar_if_only_one_tab = true,

        # https://github.com/wezterm/wezterm/issues/695#issuecomment-820160764
        adjust_window_size_when_changing_font_size = false

        ssh_domains = {
          {
            name = 'bj',
            remote_address = 'bj.c.googlers.com',
            username = 'jackmanb',
            -- For some reason the nix profile doesn't appear in the $PATH as seen by
            -- SSH, maybe that's only for interactive shell.
            remote_wezterm_path = '${config.home.homeDirectory}/.nix-profile/bin/wezterm';
          },
        }
      }
    '';
  };
}
