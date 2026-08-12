{ inputs, self, ... }:
{
  perSystem =
    {
      system,
      pkgs,
      ...
    }:
    {
      # Override pkgs with nixpkgs that has my overlays and config. This
      # approach for configuring nixpkgs is documented here:
      # https://flake.parts/system.html#approach-2-configure-pkgs-once-in-persystem
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
          inputs.deploy-rs.overlays.default
          inputs.agenix.overlays.default
          inputs.llm-agents.overlays.shared-nixpkgs
          (final: prev: {
            sashiko = inputs.sashiko.packages.${system}.default;
          })
        ];
        config.allowUnfree = true;
      };
      # This is slightly less standard, we're adding a custom module
      # argument for pkgsUnstable. Before I adopted flake-parts, I did this
      # by using specialArgs.
      _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    };
}
