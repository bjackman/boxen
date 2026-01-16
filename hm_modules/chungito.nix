{
  bjackman.nix-warmups = [
    {
      flakeRef = "github:bjackman/boxen/master#nixosConfigurations.norte.config.system.build.toplevel";
      buildArgs = [
        "--extra-substituters"
        "https://nixos-raspberrypi.cachix.org"
        "--extra-trusted-public-keys"
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    }
    # The deploy-rs deployment requires some Aarch64 Rust binary which means we
    # have to compile the cross-rustc lol.
    "github:bjackman/boxen/master#deploy.nodes.norte.profiles.system.path"
  ];
}
