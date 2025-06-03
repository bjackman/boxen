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
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."brendan" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./home.nix ];
      };
    };
}
