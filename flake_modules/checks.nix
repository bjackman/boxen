{ inputs, config, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    {
      # Check all NixOS systems and Home Manager configurations build.
      checks =
        with inputs.nixpkgs.lib;
        (mapAttrs (_: conf: conf.config.system.build.toplevel) (
          filterAttrs (_: c: c.pkgs.stdenv.hostPlatform.system == system) config.flake.nixosConfigurations
        ))
        // (mapAttrs (_: conf: conf.activationPackage) config.flake.homeConfigurations)
        // {
          heating = pkgs.callPackage ../tests/heating.nix { };
          slop-deploy = pkgs.callPackage ../tests/slop-deploy.nix { };
        };
    };
}
