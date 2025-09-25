{
  config,
  ...
}:
{
  imports = [ ./brendan.nix ];
  programs.zed-editor.enable = true;
  common.config-checkout = "${config.home.homeDirectory}/src/boxen";
}
