{
  config,
  pkgs,
  lib,
  ...
}:
{
  options = {
    common.appConfigDirs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.pathInStore);
      default = { };
      description = ''
        Attribute set mapping application names to lists of config directories.
        Each directory will be merged using symlinkJoin and deployed to
        ~/.config/$appName/.
      '';
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
      file = lib.mapAttrs' (appName: configDirs:
        lib.nameValuePair ".config/${appName}/" {
          source = pkgs.symlinkJoin {
            name = "${appName}-config";
            paths = configDirs;
          };
          recursive = true;
        }
      ) config.common.appConfigDirs //
      {

        ".config/gdb/gdbinit" = {
          source = ../files/common/config/gdb/gdbinit;
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
    common.appConfigDirs = {
      fish = [ ../files/common/config/fish ];
    };

    programs.zed-editor = {
      enable = true;
      # Don't install it - I'll take care of that separately (probably via
      # Flatpak) since I'm not using NixOS and installing graphical programs
      # from Nix is a pain.
      package = null;
      userSettings = {
        vim_mode = true;
        base_keymap = "VSCode";
      };
      userKeymaps = [
        {
          context = "Workspace";
          bindings = {
            "ctrl-x 2" = "pane::SplitVertical";
            "ctrl-x 1" = "pane::JoinAll";
            "ctrl-x k" = "pane::CloseActiveItem";
          };
        }
        {
          context = "Editor";
          bindings = {
            "ctrl-f" = "buffer_search::Deploy";
            "alt-." = "editor::GoToDefinition";
            "ctrl-t" = "pane::GoBack";
            "ctrl-d" = "editor::SelectNext";
            "ctrl-v" = "vim::Paste";
            "ctrl-x" = null;
            "ctrl-x o" = "workspace::ActivateNextPane";
            "ctrl-x r" = "editor::ReloadFile";
            "ctrl-c /" = "editor::ToggleComments";
            "alt-?" = "editor::FindAllReferences";
            "ctrl-R" = ["projects::OpenRecent" {create_new_window = false;}];
          };
        }
      ];
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
  };
}
