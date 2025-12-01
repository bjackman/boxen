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
    ./monitors.nix
  ];

  wayland.windowManager.sway.config.input = {
    "type:touchpad" = {
      pointer_accel = "0.7";
    };
  };
}
