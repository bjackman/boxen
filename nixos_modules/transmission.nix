{
  pkgs,
  config,
  agenix,
  ...
}:
{
  imports = [
    ./brendan.nix
    ./ports.nix
    ./iap.nix
    agenix.nixosModules.default
  ];

  bjackman.ports = {
    transmission = { };
  };

  bjackman.iap.services.transmission = {
    port = config.bjackman.ports.transmission.port;
    allowedUsers = [ "brendan" ];
  };

  services.transmission = {
    package = pkgs.transmission_4;
    enable = true;
    openRPCPort = true;
    settings = {
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      # Transmission's anti-DNS-rebinding host check only allows localhost by
      # default, which rejects RPC calls arriving with the proxy's Host header
      # (transmission.home.yawn.io). Disable it so the UI works through the IAP
      # proxy.
      rpc-host-whitelist-enabled = false;
      # Trust the LAN baby, I trust this LAN with my life, very trustworth LAN
      rpc-authentication-required = false;
      rpc-port = config.bjackman.ports.transmission.port;
    };
  };
  systemd.services.transmission.serviceConfig.StateDirectoryMode = "0755";
}
