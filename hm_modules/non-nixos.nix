{
  pkgs,
  config,
  nixpkgs, # from specialArgs
  ...
}:
{
  bjackman.appConfigDirs.fish = [ ../hm_files/non_nixos/config/fish ];

  # Set up the flake registry for nixpkgs to point to the version used by this
  # configuration, which means you can do `nix run nixpkgs#foo` and not have to
  # download the latest unstable nixpkgs.
  # IIRC this happens automatically at the system level on NixOS, I need to
  # figure out how that works to see if there's a way to avoid the nixpkgs
  # special arg here.
  nix.registry.nixpkgs.flake = nixpkgs;

  systemd.user.systemctlPath = "/usr/bin/systemctl";

  bjackman.nix-warmups = [
    # Note this might not actually be the configuration we're currently
    # building (e.g. we might be building a config named $USER@$HOST). But
    # this is probably similar enough that it's helpful to have it warm.
    "github:bjackman/boxen/master#homeConfigurations.${config.home.username}.activationPackage"
  ];
}
