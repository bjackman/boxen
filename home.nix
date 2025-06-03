{ config, pkgs, ... }:

{
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";

    stateVersion = "25.05";

    packages = with pkgs; [ hello ];

    # Home Manager is pretty good at managing dotfiles. The primary way to manage
    # plain files is through 'home.file'.
    file = {
      # You can configure some Fish stuff through Nix, but experimentally it
      # seems you can also just dump files into the home directory and things
      # work OK.
      ".config/fish/functions/" = {
        source = ./fish/functions;
        recursive = true;
      };

      # # Building this configuration will create a copy of 'dotfiles/screenrc' in
      # # the Nix store. Activating the configuration will then make '~/.screenrc' a
      # # symlink to the Nix store copy.
      # ".screenrc".source = dotfiles/screenrc;

      # # You can also set the file content immediately.
      # ".gradle/gradle.properties".text = ''
      #   org.gradle.console=verbose
      #   org.gradle.daemon.idletimeout=3600000
      # '';
    };
  };

  programs.home-manager.enable = true;
  programs.fish.enable = true;
}
