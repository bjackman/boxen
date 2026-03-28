{ config, ... }:
{
  imports = [
    ./ports.nix
    ./iap.nix
  ];

  bjackman.ports.silverbullet = { };

  bjackman.iap.services.silverbullet = {
    port = config.bjackman.ports.silverbullet.port;
  };

  services.silverbullet = {
    enable = true;
    openFirewall = true;
    listenPort = config.bjackman.ports.silverbullet.port;
  };
}
