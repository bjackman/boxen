# See arr/deploy.nix for more interesting comments.
{ pkgs, homelab }:
pkgs.writeShellApplication {
  name = "deploy-arr-tf";
  runtimeInputs = [
    (pkgs.callPackage ./arr/deploy.nix { inherit homelab; })
  ];
  text = ''
    deploy-arr-tf
  '';
}
