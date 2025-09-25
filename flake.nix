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
  };
  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      limmat,
      agenix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (pkgs.lib.getName pkg) [
            "claude-code"
          ];
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

      homeConfigurations =
        let
          mkConfig =
            { modules }:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./modules/common.nix
                ./modules/lkml.nix
                ./modules/chungito-ctrl.nix
                ./modules/git.nix
                ./modules/zed.nix
                ./modules/scripts.nix
                agenix.homeManagerModules.default
              ]
              ++ modules;
              extraSpecialArgs = { inherit pkgsUnstable; };
            };
        in
        {
          brendan = mkConfig { modules = [ ./modules/brendan.nix ]; };
          "brendan@chungito" = mkConfig {
            modules = [
              ./modules/brendan.nix
              ./modules/chungito.nix
            ];
          };
          jackmanb = mkConfig { modules = [ ./modules/jackmanb.nix ]; };
        };

      devShells."${system}".default = pkgs.mkShell {
        packages = [
          home-manager.packages."${system}".default
          limmat.packages."${system}".default
          agenix.packages."${system}".default
          pkgs.nix-diff
        ];
      };
    };

}
