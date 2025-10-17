# Ubuntu laptop
{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./brendan.nix
    ./non-nixos.nix
  ];
}
