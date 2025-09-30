# Corp laptop
{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./jackmanb.nix
    ./sway.nix
  ];
}
