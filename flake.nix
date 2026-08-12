{
  description = "Home Manager configuration of brendan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
      url = "github:bjackman/jellarr/network-settings";
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
    # This was set up before stock NixOS supported the Pi5.
    # Alternatives: raspberry-pi-nix: Archived for unclear reasons
    # https://discourse.nixos.org/t/what-happened-to-raspberry-pi-nix/62417.
    # nixos-hardware has support for raspberry-pi but unclear how to actually
    # use it.
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      # Don't set input.nixpkgs.follows because this nixos-raspberrypi thing is
      # pretty fucked up and overrides its nixpkgs in weird ways.
      # (Hopefully fixed when https://github.com/nvmd/nixos-raspberrypi/pull/131
      # is merged)
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    sashiko = {
      url = "github:bjackman/sashiko?ref=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    tvheadend = {
      url = "github:tvheadend/tvheadend";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
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
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }: {
        # We actually build Arm stuff too, but we don't need them as package
        # outputs.
        systems = [ "x86_64-linux" ];
        imports = [
          ./flake_modules/home.nix
          ./flake_modules/hosts.nix
          ./flake_modules/checks.nix
          ./flake_modules/deploy.nix
          ./flake_modules/formatting.nix
          ./flake_modules/packages.nix
          ./flake_modules/devShells.nix
          inputs.treefmt-nix.flakeModule
        ];
      }
    );
}
