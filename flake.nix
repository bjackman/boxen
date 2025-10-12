{
  description = "Home Manager configuration of brendan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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
    impermanence.url = "github:nix-community/impermanence";
    declarative-jellyfin = {
      url = "github:Sveske-Juice/declarative-jellyfin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      limmat,
      agenix,
      impermanence,
      declarative-jellyfin,
      deploy-rs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
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
      };
    in
    {
      formatter."${system}" = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

      checks."${system}".default =
        pkgs.runCommand "check-nix-format"
          {
            nativeBuildInputs = [ pkgs.nixfmt-rfc-style ];
            src = nixpkgs.lib.fileset.toSource {
              root = ./.;
              fileset = nixpkgs.lib.fileset.gitTracked ./.;
            };
            output = "/dev/null";
          }
          ''
            for file in $(find $src -name "*.nix"); do
              nixfmt --check $file
            done
            touch $out
          '';

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
          notmuch-propagate-mute = final.callPackage ./packages/notmuch-propagate-mute.nix { };
        };
      };

      packages."${system}" = pkgs.bjackman;

      # This defines the configurations for machines using standalone
      # home-manager, which in my case means machines not running NixOS.
      # Otherwise the HM config is injected via the NixOS module.
      homeConfigurations = {
        "brendan@brendan-thinkpad" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./hm_modules/brendan.nix
            ./hm_modules/non-nixos.nix
          ];
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
          modules = [
            ./hm_modules/jackmanb01.nix
          ];
          extraSpecialArgs = hmSpecialArgs;
        };
      };

      nixosConfigurations.chungito = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./nixos_modules/chungito
          impermanence.nixosModules.impermanence
          agenix.nixosModules.default
          declarative-jellyfin.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = hmSpecialArgs;
              users.brendan = {
                imports = [
                  ./hm_modules/chungito.nix
                  ./hm_modules/nixos.nix
                ];
              };
            };
          }
        ];
      };

      nixosConfigurations.norte = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          agenix.nixosModules.default
          ./nixos_modules/norte.nix
        ];
      };
      deploy.nodes.norte = {
        hostname = "norte";
        interactiveSudo = true;
        profiles.system = {
          user = "root";
          path = pkgsCross.deploy-rs.lib.activate.nixos self.nixosConfigurations.norte;
        };
      };

      devShells."${system}".default = pkgs.mkShell {
        packages = [
          home-manager.packages."${system}".default
          limmat.packages."${system}".default
          agenix.packages."${system}".default
          pkgs.nix-diff
          declarative-jellyfin.packages."${system}".genhash
          deploy-rs.packages.x86_64-linux.default
        ];
      };
    };

}
