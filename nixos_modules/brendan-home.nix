# This defines NixOS systems that have my Home Manager configuration set up.
{
  inputs,
  home-manager,
  pkgsUnstable,
  ...
}:
{
  imports = [ home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users.brendan = {
      imports = [
        ../hm_modules/common.nix
        ../hm_modules/brendan.nix
        ../hm_modules/nixos.nix
      ];
    };

    extraSpecialArgs = inputs // {
      inherit pkgsUnstable;
    };
  };
}
