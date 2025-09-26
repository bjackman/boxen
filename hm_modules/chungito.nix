{
  config,
  pkgsUnstable,
  ...
}:
{
  imports = [ ./brendan.nix ];
  common.config-checkout = "${config.home.homeDirectory}/src/boxen";
  programs.zed-editor = {
    enable = true;
    package = pkgsUnstable.zed-editor;
  };
}
