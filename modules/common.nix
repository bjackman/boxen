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
      fortune
      cowsay
      clolcat
    ];
    programs.bash.enable = true;

    # Note awkward relative path here. Alternative would be to communicate a
    # base path for these files via specialArgs based on the flake's `self`.
    common.fishConfigDirs = [ ../files/common/config/fish ];
  };
}
