{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./common.nix
    ./brendan.nix
    ./sway.nix
    ./home-monitors.nix
  ];
}
