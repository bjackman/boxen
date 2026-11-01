{ inputs, config, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    {
      # Check all NixOS systems and Home Manager configurations build.
      checks =
        with inputs.nixpkgs.lib;
        (mapAttrs (name: _: config.flake.nixosConfigurations.${name}.config.system.build.toplevel) (
          filterAttrs (_: host: host.system == system) config.bjackman.hosts
        ))
        // (mapAttrs (_: conf: conf.activationPackage) config.flake.homeConfigurations)
        // {
          heating = pkgs.callPackage ../tests/heating.nix { };
          slop-deploy = pkgs.callPackage ../tests/slop-deploy.nix { };
          slopops-chat = pkgs.callPackage ../tests/slopops-chat.nix { };
        };
    };
}
