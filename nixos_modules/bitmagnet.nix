{ config, ... }:
let
  ports = config.bjackman.ports;
in
{
  imports = [
    ./iap.nix
    ./postgres.nix
  ];

  bjackman.ports = {
    bitmagnet = { };
  };
  bjackman.iap.services.bitmagnet = {
    port = config.bjackman.ports.bitmagnet.port;
  };

  services.bitmagnet = {
    enable = true;
    openFirewall = true;
    # Only the first N files of each torrent are kept - torrent_files
    # otherwise dominates the DB. Not lower: the classifier detects content
    # type by summing file sizes per extension, so over-truncating makes it
    # misclassify large torrents.
    settings.dht_crawler.save_files_threshold = 10;
    settings.http_server = rec {
      # For some reason this is a string, and also it's wrong, the correct
      # option seems to be local_address:
      # https://github.com/NixOS/nixpkgs/issues/483666
      port = ":${builtins.toString ports.bitmagnet.port}";
      local_address = port;
    };
  };
  # openFirewall only opens the DHT port, also open the web UI port.
  networking.firewall.allowedTCPPorts = [ ports.bitmagnet.port ];
}
