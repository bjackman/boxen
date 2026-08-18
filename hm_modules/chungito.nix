{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./homelab-ctrl.nix
    ./pc.nix
  ];

  bjackman.nix-warmups =
    let
      buildArgs = [
        "--extra-substituters"
        "https://nixos-raspberrypi.cachix.org"
        "--extra-trusted-public-keys"
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    in
    [
      {
        flakeRef = "github:bjackman/boxen/master#nixosConfigurations.norte.config.system.build.toplevel";
        inherit buildArgs;
      }
      {
        # The deploy-rs deployment requires some Aarch64 Rust binary which means we
        # have to compile the cross-rustc lol.
        flakeRef = "github:bjackman/boxen/master#deploy.nodes.norte.profiles.system.path";
        inherit buildArgs;
      }
    ];

  # https://wiki.nixos.org/wiki/Zed#Remote_server
  home.file.".zed_server" = {
    source = "${pkgs.zed-editor.remote_server}/bin";
    recursive = true;
  };

  home.packages = with pkgs; [
    btop-cuda
    mixxx
  ];

  bjackman.waybar.showKeyboardLayout = true;

  wayland.windowManager.sway.config = {
    input."*".xkb_layout = "us,ch";
    keybindings =
      let
        mod = config.wayland.windowManager.sway.config.modifier;
      in
      {
        "${mod}+space" = lib.mkForce "input type:keyboard xkb_switch_layout next";
      };
  };
}
