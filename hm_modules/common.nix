{
  config,
  pkgs,
  lib,
  agenix,
  nixpkgs-unstable, # from specialArgs
  ...
}:
{
  imports = [
    ./lkml.nix
    ./chungito-ctrl.nix
    ./git.nix
    ./vscode.nix
    ./zed.nix
    ./scripts.nix
    agenix.homeManagerModules.default
  ];

  options = {
    bjackman.appConfigDirs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.pathInStore);
      default = { };
      description = ''
        Attribute set mapping application names to lists of config directories.
        Each directory will be merged using symlinkJoin and deployed to
        ~/.config/$appName/.
      '';
    };

    # So that we can place links directly to the contents of the home-manager
    # config checkout, we define an option to tell the system where that is.
    # Code cribbed from:
    # https://github.com/nix-community/home-manager/issues/2085#issuecomment-2022239332
    bjackman.configCheckout = lib.mkOption {
      type = lib.types.path;
      apply = toString;
      default = "${config.xdg.configHome}/home-manager";
      description = "Place where the home-manager configuration is checked out locally.";
    };
  };

  config = {
    home = {
      stateVersion = "25.05";

      # This implements the appConfigDirs thing. lib.mapAttrs' and
      # lib.nameValuePair are sorta complementary functions, the former takes an
      # attrset and for each key/value pair it calls the callback with those as
      # the two args (here appName and configDirs). Then nameValuePair gives you
      # the right format to return from this callback so that lib.mapAttrs' can
      # combine the results into an attrset. So we end up setting
      # file.".config/${appName}" = { source = ... }.
      file =
        lib.mapAttrs' (
          appName: configDirs:
          lib.nameValuePair ".config/${appName}/" {
            source = pkgs.symlinkJoin {
              name = "${appName}-config";
              paths = configDirs;
            };
            recursive = true;
          }
        ) config.bjackman.appConfigDirs
        // {

          ".config/gdb/gdbinit" = {
            source = ../hm_files/common/config/gdb/gdbinit;
          };
        };

      sessionVariables = {
        EDITOR = "vim";
      };
    };

    programs.home-manager.enable = true;

    home.packages = with pkgs; [
      # Stuff for The Turt
      fortune
      cowsay
      clolcat

      nix-tree
      hunspell
      bat
    ];
    programs.bash.enable = true;

    programs.fish = {
      enable = true;
      plugins = [
        {
          name = "z";
          src = pkgs.fishPlugins.z.src;
        }
      ];
    };
    # Note awkward relative path here. Alternative would be to communicate a
    # base path for these files via specialArgs based on the flake's `self`.
    bjackman.appConfigDirs = {
      fish = [ ../hm_files/common/config/fish ];
    };

    # This is the configuration for decrypting secrets. This will cause the
    # secrets to be decrypted and dumped into a tmpfs as plaintext. The path of
    # that plaintext file will be available as
    # config.age.secrets."${name}".path.
    # Note that the key used to decrypt them is left implicit so it will look at
    # the general SSH configuration and pick a sensitible default.
    age.secrets = {
      eadbald-pikvm-password.file = ../secrets/eadbald-pikvm-password.age;
    };

    programs.tmux = {
      enable = true;
      mouse = true;
      historyLimit = 50000;
      terminal = "xterm-256color";
      shell = "${pkgs.fish}/bin/fish";
      # I don't know what xterm-keys does, copied it blindly from my old
      # dotfiles.
      extraConfig = ''
        set-window-option -g xterm-keys on

        bind-key h select-pane -L
        bind-key l select-pane -R
        bind-key k select-pane -U
        bind-key j select-pane -D

        set -as terminal-features ",*:hyperlinks"
      '';
    };

    programs.kitty = {
      enable = true;
      settings = {
        enable_audio_bell = false;
        allow_remote_control = true;
        # This configures the separate scrollback buffer that is only accessible
        # via the pager magic, not the "live" scrollback that you can interact
        # with via the mouse. It's recommended to keep the latter small for perf.
        # Megabytes.
        scrollback_pager_history_size = 128;
      };
    };
    # Allow creating new terminals on remote hosts (connected via kitten ssh).
    # Note when using this in corp you lose the reconnection ability from
    # roadwarrior/gmosh.
    programs.fish.shellAbbrs.klo = "kitty @ launch --type=os-window --cwd=current fish";

    nix.registry.nixpkgs-unstable.flake = nixpkgs-unstable;
  };
}
