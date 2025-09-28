{
  pkgs,
  ...
}:
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };
  programs.hyprlock.enable = true;
  environment.systemPackages = [
    pkgs.kitty # required for the default Hyprland config
  ];
}
