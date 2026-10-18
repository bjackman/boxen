{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bjackman.nixCache;
  port = config.bjackman.ports.nix-cache.port;
in
{
  imports = [
    ./ports.nix
  ];

  options.bjackman.nixCache.serve = lib.mkEnableOption "serving this host's Nix store as a binary cache";

  config = lib.mkIf cfg.serve {
    bjackman.ports.nix-cache = { };

    age.secrets.nix-cache-signing-key.file = ../secrets/nix-cache-signing-key.age;

    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [ config.age.secrets.nix-cache-signing-key.path ];
      settings = {
        bind = "[::]:${toString port}";
        # Ahead of cache.nixos.org's 40.
        priority = 30;
      };
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
  };
}
