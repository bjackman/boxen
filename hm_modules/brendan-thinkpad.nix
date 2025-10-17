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
    ./sway.nix
    ./home-monitors.nix
  ];
}
