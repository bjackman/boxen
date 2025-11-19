{
  pkgs,
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
}