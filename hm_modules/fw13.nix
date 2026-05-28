{
  imports = [
    ./pc.nix
    ./ssh-server.nix
  ];

  wayland.windowManager.sway.config.input = {
    "type:touchpad" = {
      pointer_accel = "0.7";
    };
  };
}
