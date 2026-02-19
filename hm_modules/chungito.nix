{ pkgs, ... }:
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

  # https://wiki.nixos.org/wiki/Zed#Remote_server
  home.file.".zed_server" = {
    source = "${pkgs.zed-editor.remote_server}/bin";
    recursive = true;
  };

  # Needed so I can run the Terraform deploy script
  age.secrets = {
    arr-api-key.file = ../secrets/arr-api-key.age;
    transmission-password.file = ../secrets/transmission-password.age;
  };
}
