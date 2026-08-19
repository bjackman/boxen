{
  inputs,
  config,
  withSystem,
  ...
}:
{
  imports = [
    ./nixpkgs.nix
    ./homelab.nix
  ];

  flake.nixosConfigurations =
    let
      mkNixosSystem =
        {
          system,
          modules,
          builder ? inputs.nixpkgs.lib.nixosSystem,
        }:
        withSystem system (
          { pkgs, pkgsUnstable, ... }:
          builder {
            inherit system modules;
            # Squashing the inputs into specialArgs let's you refer to flake
            # inputs in modules, which lets you declare imports closer to the code
            # that depends on them. For example this means you can import the
            # impermanence module near the code that set up impermanence settings.
            #
            # Note a slightly weird thing about this: we're splatting the contents
            # of `inputs` into the specialArgs, but also setting an arg called
            # `inputs`. The former is coz I already have a bunch of code that
            # directly refers to inputs by their name in module args, the latter
            # is because I still need to pass the whole `inputs` through as a unit
            # from the NixOS module system into the Home Manager module system.
            specialArgs = inputs // {
              inherit inputs pkgsUnstable;
              inherit (config.bjackman) homelab;
            };
          }
        );
    in
    {
      chungito = mkNixosSystem {
        system = "x86_64-linux";
        modules = [
          ../nixos_modules/chungito
          { home-manager.users.brendan.imports = [ ../hm_modules/chungito.nix ]; }
        ];
      };
      fw13 = mkNixosSystem {
        system = "x86_64-linux";
        modules = [
          ../nixos_modules/fw13
          { home-manager.users.brendan.imports = [ ../hm_modules/fw13.nix ]; }
        ];
      };
      # Raspberry Pi 4B at my mum's place.
      sandy = mkNixosSystem {
        system = "aarch64-linux";
        modules = [ ../nixos_modules/sandy.nix ];
      };
      # Thinkpad t480 at my place
      pizza = mkNixosSystem {
        system = "x86_64-linux";
        modules = [ ../nixos_modules/pizza ];
      };
      norte = mkNixosSystem {
        system = "aarch64-linux";
        modules = [ ../nixos_modules/norte ];
        # Raspberry Pi 5 with a Radxa SATA hat at my place.
        # Note this is using a special nixosSystem helper. Raspberry Pi 5s
        # are fucked up and someone made it work, so, well, we're gonna go
        # with it.
        builder = inputs.nixos-raspberrypi.lib.nixosSystem;
      };
      slopbox = mkNixosSystem {
        system = "x86_64-linux";
        modules = [
          ../nixos_modules/slopbox.nix
        ];
      };
    };

  # This defines the configurations for machines using standalone
  # home-manager, which in my case means machines not running NixOS.
  # Otherwise the HM config is injected via the NixOS module.
  flake.homeConfigurations = withSystem "x86_64-linux" (
    { pkgs, pkgsUnstable, ... }: {
      brendan = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ../hm_modules/brendan.nix
          ../hm_modules/workstation.nix
        ];
        extraSpecialArgs = inputs // {
          inherit pkgsUnstable;
          inherit (config.bjackman) homelab;
        };
      };
      niamh = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ../hm_modules/niamh.nix ];
      };
    }
  );
}
