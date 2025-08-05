{
  config,
  pkgs,
  lib,
  ...
}:
{
  options = {
    common.fishConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.pathInStore;
      default = [ ];
      description = ''
        Derivations producing directories with fish configs, will be combined
        into a single config using symlinkJoin.
      '';
    };
  };

  config = {
    home = {
      stateVersion = "25.05";

      file = {
        # You can configure some Fish stuff through Nix, but experimentally it
        # seems you can also just dump files into the home directory and things
        # work OK.
        ".config/fish/" =
          let
            fishConfig = pkgs.symlinkJoin {
              name = "fish-config";
              paths = [ config.common.fishConfigDirs ];
            };
          in
          {
            source = fishConfig;
            recursive = true;
          };

        ".config/gdb/gdbinit" = {
          source = ../files/common/config/gdb/gdbinit;
        };
      };

      sessionVariables = {
        EDITOR = "vim";
      };
    };

    programs.home-manager.enable = true;

    programs.fish = {
      enable = true;
      plugins = [
        {
          name = "z";
          src = pkgs.fishPlugins.z.src;
        }
      ];
    };
    home.packages = with pkgs; [
      # Stuff for The Turt
      fortune
      cowsay
      clolcat

      nix-tree
    ];
    programs.bash.enable = true;

    # Note awkward relative path here. Alternative would be to communicate a
    # base path for these files via specialArgs based on the flake's `self`.
    common.fishConfigDirs = [ ../files/common/config/fish ];

    # This is the configuration for decrypting secrets. This will cause the
    # secrets to be decrypted and dumped into a tmpfs as plaintext. The path of
    # that plaintext file will be available as
    # config.age.secrets."${name}".path.
    # Note that the key used to decrypt them is left implicit so it will look at
    # the general SSH configuration and pick a sensitible default.
    age.secrets = {
      eadbald-pikvm-password.file = ../secrets/eadbald-pikvm-password.age;
    };
  };
}
