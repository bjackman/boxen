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

  wayland.windowManager.sway.config.output = {
    # Center monitor
    "Lenovo Group Limited P27h-20 V906YLCP" = {
      position = "0 0";
    };
    # To the right of the Lenovo one
    "Samsung Electric Company LS27A600U HNMR402251" = {
      position = "2560 0";
    };
    # Below the lenovo one
    "BOE 0x0C00 Unknown" = {
      position = "0 1440";
    };
  };
}
