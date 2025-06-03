{ config, pkgs, ... }:

{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";

    stateVersion = "25.05";

    packages = with pkgs; [ hello ];

    file = {
      # You can configure some Fish stuff through Nix, but experimentally it
      # seems you can also just dump files into the home directory and things
      # work OK.
      ".config/fish/" = {
        source = ./fish;
        recursive = true;
      };
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
}
