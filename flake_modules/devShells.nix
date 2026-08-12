{ inputs, ... }:
{
  perSystem =
    {
      system,
      pkgs,
      inputs',
      ...
    }:
    {
      devShells = {
        default = pkgs.mkShell {
          packages = [
            inputs'.home-manager.packages.default
            inputs'.limmat.packages.default
            pkgs.agenix
            pkgs.nix-diff
            pkgs.nixos-rebuild
            inputs'.deploy-rs.packages.default
            pkgs.perses # For percli
            pkgs.cue
            pkgs.opentofu
          ];
        };
        homepage = pkgs.mkShell {
          packages = [
            pkgs.pandoc
            pkgs.python3 # For python3 -m http.server
          ];
        };
      };
    };
}
