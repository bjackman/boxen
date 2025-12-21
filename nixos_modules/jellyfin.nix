{
  config,
  pkgs,
  agenix,
  ...
}:
{
  # Note this is just the generic parts of the config, individual machines will
  # need more specific configs. It also doesn't actually enable jellyfin.

  imports = [
    agenix.nixosModules.default
  ];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
}
