{ pkgs, config, ... }:
{
  imports = [
    ./common.nix
    ./non-nixos.nix
    ./wezterm.nix
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

  programs.git.settings = {
    user = {
      email = "jackmanb@google.com";
      name = "Brendan Jackman";
    };
    # To be honest I'm not 100% sure exactly what this does.
    url."sso://user".insteadOf = "https://user.git.corp.google.com";
    # Use the gLinux SSH since the Nix one doesn't know about Google
    # weirdness.
    core.sshCommand = "/usr/bin/ssh";
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
    matchBlocks."bj".hostname = "bj.c.googlers.com";
    matchBlocks."*" = {
      controlMaster = "auto";
      controlPersist = "8h";
      controlPath = "~/.ssh/master-%r@%n:%p";
      forwardAgent = true; # For gnubby
    };
    # systemd-ssh-proxy doesn't seem to play nice with ControlMaster, but also
    # it isn't useful there anyway.
    matchBlocks."unix/* unix%* vsock/* vsock%* vsock-mux/* vsock-mux%* machine/* machine%*".controlMaster =
      "no";
    # To pre-empt deprecation of default values:
    enableDefaultConfig = false;
  };

  bjackman.wezterm.extraConfig = ''
    config.ssh_domains = {
      {
        name = 'bj',
        remote_address = 'bj.c.googlers.com',
        username = 'jackmanb',
        -- For some reason the nix profile doesn't appear in the $PATH as seen by
        -- SSH, maybe that's only for interactive shell.
        remote_wezterm_path = '${config.home.homeDirectory}/.nix-profile/bin/wezterm';
      },
    };
  '';
}
