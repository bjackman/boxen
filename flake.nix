{
  description = "Home Manager configuration of brendan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    limmat = {
      url = "github:bjackman/limmat";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix-template.url = "github:jhillyerd/agenix-template";
    impermanence.url = "github:nix-community/impermanence";
    jellarr = {
      url = "github:venkyr77/jellarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Alternatives: raspberry-pi-nix: Archived for unclear reasons
    # https://discourse.nixos.org/t/what-happened-to-raspberry-pi-nix/62417.
    # nixos-hardware has support for raspberry-pi but unclear how to actually
    # use it.
    nixos-raspberrypi = {
      # Using the 'develop' branch since that's synced to 25.11
      url = "github:nvmd/nixos-raspberrypi/develop";
      # Don't set input.nixpkgs.follows because this nixos-raspberrypi thing is
      # pretty fucked up and overrides its nixpkgs in weird ways.
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  # Not really sure if this works. Not really sure if it's needed. Disable it
  # so we can at least avoid using it for other nodes than Norte.
  # nixConfig = {
  #   extra-substituters = [
  #     "https://nixos-raspberrypi.cachix.org"
  #   ];
  #   extra-trusted-public-keys = [
  #     "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
  #   ];
  # };
  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      limmat,
      agenix,
      agenix-template,
      impermanence,
      disko,
      deploy-rs,
      nixos-hardware,
      nixos-raspberrypi,
      treefmt-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
          deploy-rs.overlays.default
        ];
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (pkgs.lib.getName pkg) [
            "spotify"
          ];
      };
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (pkgs.lib.getName pkg) [
            "claude-code"
          ];
      };
      # This is a rather bananas dance to create a cross-compiled deploy-rs.
      # There is a binary in there that needs to be build for the target
      # architecture, so this sets up a version of nixpkgs that's cross-compiled
      # to aarch64. Then deploy-rs provides an overlay that will build the
      # package via this cross compilation. This does still require building
      # rustc though lmao.
      # Note this ISN'T used for the actual NixOS system, for that it's just
      # built "natively" so you'll need the binfmt_misc magic to make it work.
      # That is fine in practice because you just get everything from the binary
      # cache.
      # https://nixos.wiki/wiki/Cross_Compiling has a section about "lazy
      # cross-compiling" that seems like a more elegant way to achieve something
      # kinda similar to this.
      pkgsCross = import nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = {
          config = "aarch64-unknown-linux-gnu";
        };
        overlays = [ deploy-rs.overlays.default ];
      };
      # Hm. This is how I'm passing in stuff to my home manager modules that
      # needs to be a flake input. This seems kinda yucky, I think I'm doing
      # something wrong here. For the NixOS modules below, instead of injecting
      # the flake inputs via specialArgs, I just listed them explicitly where I
      # instantiate the config. For the pkgsUnstable thing, an alternative would
      # just be to inject the pacakges into pkgs, via an overlay.
      hmSpecialArgs = {
        inherit pkgsUnstable;
        inherit agenix;
        inherit nixpkgs;
        inherit nixpkgs-unstable;
      };
      treefmtCfg = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.mdformat.enable = true;
      };
    in
    {
      formatter."${system}" = treefmtCfg.config.build.wrapper;

      # This is a bit of a magical dance to get packages defined in this flake
      # to be available as flake outputs (so they can easily be tested) and also
      # exposed into the Home Manager module system. We define the packages in a
      # nixpkgs overlay. We then consume the overlay into pkgs above (so Home
      # Manager modules can consume the packages). Then we expose them as flake
      # outputs here below.
      # Note the overlay itself is system-agnostic, it's just a function that
      # refers to whatever nixpkgs instance it's called on.
      # https://discourse.nixos.org/t/multiple-packages-in-the-same-flake-that-depend-on-each-other/69673/5
      overlays.default = final: prev: {
        # Put all the packages defined this way under the "bjackman" key so it's
        # obvious at the usage site that they come from an overlay.
        bjackman = {
          notmuch-propagate-mute = final.callPackage ./packages/notmuch-propagate-mute { };
          spellcheck_commitmsg = final.callPackage ./packages/spellcheck_commitmsg { };
          spellcheck_commitmsgs = final.callPackage ./packages/spellcheck_commitmsgs { };
        };
      };

      packages."${system}" = pkgs.bjackman // {
        # This is really a "check" but having it in there is super fucking
        # annoying because it causes deploy-rs to fail. So, just put it as a
        # package and we can have Limmat build it.
        format = treefmtCfg.config.build.check self;
      };

      # This defines the configurations for machines using standalone
      # home-manager, which in my case means machines not running NixOS.
      # Otherwise the HM config is injected via the NixOS module.
      homeConfigurations = {
        brendan = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ ./hm_modules/brendan.nix ];
          extraSpecialArgs = hmSpecialArgs;
        };
        jackmanb = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ ./hm_modules/jackmanb.nix ];
          extraSpecialArgs = hmSpecialArgs;
        };
        # corp laptop
        "jackmanb@jackmanb01" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ ./hm_modules/jackmanb01.nix ];
          extraSpecialArgs = hmSpecialArgs;
        };
      };

      nixosConfigurations =
        let
          brendanHome = {
            imports = [ home-manager.nixosModules.home-manager ];
            nixpkgs.overlays = [ self.outputs.overlays.default ];
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              extraSpecialArgs = hmSpecialArgs;
              users.brendan = {
                imports = [
                  ./hm_modules/common.nix
                  ./hm_modules/brendan.nix
                  ./hm_modules/sway.nix
                  ./hm_modules/monitors.nix
                  ./hm_modules/nixos.nix
                ];
              };
            };
          };
          # Squashing the inputs into specialArgs let's you refer to flake
          # inputs in modules, which lets you declare imports closer to the code
          # that depends on them. For example this means you can import the
          # impermanence module near the code that set up impermanence settings.
          specialArgs = inputs // {
            # Also allow different nodes' configs to refer to each other in
            # cases where they are coupled.
            otherConfigs = {
              nfsServer = self.nixosConfigurations.norte.config;
              sambaServer = self.nixosConfigurations.norte.config;
              jellyfinServer = self.nixosConfigurations.pizza.config;
            };
          };
        in
        {
          chungito = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./nixos_modules/chungito
              brendanHome
              { home-manager.users.brendan.imports = [ ./hm_modules/chungito.nix ]; }
            ];
            inherit specialArgs;
          };
          fw13 = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./nixos_modules/fw13
              brendanHome
            ];
            inherit specialArgs;
          };
          # Raspberry Pi 4B at my mum's place.
          sandy = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [ ./nixos_modules/sandy.nix ];
            inherit specialArgs;
          };
          # Thinkpad t480 at my place
          pizza = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./nixos_modules/pizza ];
            inherit specialArgs;
          };
          # Raspberry Pi 5 with a Radxa SATA hat at my place.
          # Note this is using a special nixosSystem helper. Raspberry Pi 5s
          # are fucked up and someone made it work, so, well, we're gonna go
          # with it.
          norte = nixos-raspberrypi.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [ ./nixos_modules/norte ];
            inherit specialArgs;
          };
        };

      deploy.nodes = {
        sandy = {
          hostname = "sandy";
          profiles.system = {
            user = "root";
            path = pkgsCross.deploy-rs.lib.activate.nixos self.nixosConfigurations.sandy;
          };
        };
        norte = {
          hostname = "norte";
          profiles.system = {
            user = "root";
            path = pkgsCross.deploy-rs.lib.activate.nixos self.nixosConfigurations.norte;
          };
        };
        pizza = {
          hostname = "pizza";
          profiles.system = {
            user = "root";
            path = pkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.pizza;
          };
        };
      };

      # Check all NixOS systems and Home Manager configurations build.
      checks."${system}" =
        (nixpkgs.lib.mapAttrs (_: conf: conf.config.system.build.toplevel) (
          nixpkgs.lib.filterAttrs (_: c: c.pkgs.stdenv.hostPlatform.system == system) self.nixosConfigurations
        ))
        // (nixpkgs.lib.mapAttrs (_: conf: conf.activationPackage) self.homeConfigurations);

      devShells."${system}".default = pkgs.mkShell {
        packages = [
          home-manager.packages."${system}".default
          limmat.packages."${system}".default
          agenix.packages."${system}".default
          pkgs.nix-diff
          pkgs.nixos-rebuild
          deploy-rs.packages.x86_64-linux.default
        ];
      };
    };

}
