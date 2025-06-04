{ config, pkgs, ... }:

{
  home = {
    stateVersion = "25.05";

    packages = with pkgs; [ hello ];

    file = {
      # You can configure some Fish stuff through Nix, but experimentally it
      # seems you can also just dump files into the home directory and things
      # work OK.
      ".config/fish/" = {
        # Note awkward relative path here. Alternative would be to communicate a
        # base path for these files via specialArgs based on the flake's `self`.
        source = ../files/fish;
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
  programs.bash.enable = true;
}
