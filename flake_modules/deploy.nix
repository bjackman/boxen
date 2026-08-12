{
  inputs,
  config,
  withSystem,
  ...
}:
{
  imports = [
    ./hosts.nix
  ];

  flake.deploy.nodes =
    let
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
      pkgsCross = import inputs.nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = {
          config = "aarch64-unknown-linux-gnu";
        };
        overlays = [ inputs.deploy-rs.overlays.default ];
      };
    in
    {
      sandy = {
        hostname = "sandy";
        profiles.system = {
          user = "root";
          path = pkgsCross.deploy-rs.lib.activate.nixos config.flake.nixosConfigurations.sandy;
        };
      };
      norte = {
        hostname = "norte";
        profiles.system = {
          user = "root";
          path = pkgsCross.deploy-rs.lib.activate.nixos config.flake.nixosConfigurations.norte;
        };
      };
      pizza = {
        hostname = "pizza";
        profiles.system = {
          user = "root";
          path = withSystem "x86_64-linux" (
            { pkgs, ... }: pkgs.deploy-rs.lib.activate.nixos config.flake.nixosConfigurations.pizza
          );
        };
      };
    };

  # Since these are laptops and we can only deploy to them when they're
  # powered on, don't put them in the "real" deploy field.
  # I don't yet know if there's any real way to deploy this. I think maybe
  # deploy-rs is not flexible enough here. Probably easiest to just deploy
  # these freaky nodes via a simple custom script. I don't think I get any
  # benefit out of higher-level tools here anyway.
  flake.extraDeploy.nodes = {
    airbuntu = {
      hostname = "airbuntu";
      sshUser = "niamh";
      profiles.home = {
        user = "niamh";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.home-manager config.flake.homeConfigurations.niamh;
      };
    };
    romy = {
      hostname = "macbook-air-8";
      sshUser = "romybinswanger";
      profiles.home = {
        user = "romybinswanger";
        path =
          let
            # Also want to avoid trying to check this configurations since
            # it can only be built with access to a Darwin builder, so we
            # hide this down here away from the main homeConfigurations
            # flake output.
            hmConfig = inputs.home-manager.lib.homeManagerConfiguration {
              pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
              modules = [ ../hm_modules/romy.nix ];
            };
          in
          inputs.deploy-rs.lib.aarch64-darwin.activate.home-manager hmConfig;
      };
    };
  };

}
