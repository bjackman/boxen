{
  description = "Home Manager configuration of brendan";

  inputs = {
    # home-manager 25.05 is not working on Ubuntu for me:
    #
    # ❯❯  nix run home-manager/release-25.05 -- switch
    # error:
    # … while updating the lock file of flake 'github:nix-community/home-manager/282e1e029cb6ab4811114fc85110613d72771dea?narHash=sha256-RMhjnPKWtCoIIHiuR9QKD7xfsKb3agxzMfJY8V9MOew%3D'
    #
    # error: cannot write modified lock file of flake 'flake:home-manager/release-25.05' (use '--no-write-lock-file' to ignore)
    #
    # It's strongly recommended to match nixpkgs and home-manager versions. So
    # use unstable for now.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    limmat = {
      url = "github:bjackman/limmat";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      limmat,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
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

      homeConfigurations =
        let
          mkConfig =
            { modules }:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./modules/common.nix
                ./modules/lkml.nix
              ]
              ++ modules;
            };
        in
        {
          brendan = mkConfig { modules = [ ./modules/brendan.nix ]; };
          jackmanb = mkConfig { modules = [ ./modules/jackmanb.nix ]; };
        };

      devShells."${system}".default = pkgs.mkShell {
        packages = [ limmat.packages."${system}".default ];
      };
    };

}
