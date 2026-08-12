{
  inputs,
  withSystem,
  ...
}:
{
  imports = [
    ./nixpkgs.nix
  ];

  # This defines the configurations for machines using standalone
  # home-manager, which in my case means machines not running NixOS.
  # Otherwise the HM config is injected via the NixOS module.
  flake.homeConfigurations = withSystem "x86_64-linux" (
    { pkgs, pkgsUnstable, ... }: {
      brendan = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ../hm_modules/brendan.nix ];
        extraSpecialArgs = inputs // {
          inherit pkgsUnstable;
        };
      };
      niamh = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ../hm_modules/niamh.nix ];
      };
    }
  );
}
