{ inputs, config, ... }:
{
  perSystem = { system, ... }: {
    # Check all NixOS systems and Home Manager configurations build.
    checks =
      with inputs.nixpkgs.lib;
      (mapAttrs (_: conf: conf.config.system.build.toplevel) (
        filterAttrs (_: c: c.pkgs.stdenv.hostPlatform.system == system) config.flake.nixosConfigurations
      ))
      // (mapAttrs (_: conf: conf.activationPackage) config.flake.homeConfigurations);
  };
}
