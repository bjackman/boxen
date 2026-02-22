{ config, ... }:
{
  imports = [
    ./ports.nix
    ./iap.nix
    ./postgres.nix
  ];

  bjackman.ports.miniflux = { };

  bjackman.iap.services.miniflux = {
    port = config.bjackman.ports.miniflux.port;
  };

  services.miniflux = {
    enable = true;
    config = {
      CREATE_ADMIN = false;

      # Take auth from headers set by reverse proxy.
      AUTH_PROXY_HEADER = "Remote-User";
      AUTH_PROXY_USER_CREATION = 1;
      LISTEN_ADDR = "127.0.0.1:${toString config.bjackman.ports.miniflux.port}";
      # If I don't do this, it rejects my IP address, I think it takes it from
      # the X-Forwarded-For header. I'm like 90% sure setting this is safe since
      # I have restricted the LISTEN_ADDR to localhost...
      TRUSTED_REVERSE_PROXY_NETWORKS = "0.0.0.0/0,::/0";

      BASE_URL = config.bjackman.iap.services.miniflux.url;
    };
  };
}
