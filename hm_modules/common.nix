{
  config,
  pkgs,
  lib,
  nixpkgs-unstable, # from specialArgs
  nix-index-database,
  agenix,
  agent-skills,
  ...
}:
{
  imports = [
    ./git.nix
    ./scripts.nix
    ./nix-warmup.nix
    nix-index-database.homeModules.default
    agenix.homeManagerModules.default
    agent-skills.outputs.homeManagerModules.default
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
        HOME_MANAGER_CONFIG_CHECKOUT = config.bjackman.configCheckout;
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
      mosh
      file
      tree
      pstree
      pciutils
      lshw
      jq
      iw
      comma
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

    nix.registry.nixpkgs-unstable.flake = nixpkgs-unstable;

    programs.agent-skills = {
      enable = true;
      sources.my-skills = {
        path = ../hm_files/skills;
      };
      skills.enable = [
        "investigate-alert"
        "investigate-kernel-patch-history"
      ];
    };
  };
}
