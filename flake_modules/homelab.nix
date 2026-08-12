{ config, lib, ... }:
{
  # This is a representation of the structure of my homelab that allows the
  # configs of each host to reach across and refer to each
  # others' options.
  options.bjackman.homelab = lib.mkOption { type = lib.types.raw; };
  config.bjackman.homelab = rec {
    # For cases where we actually care about the nodes themselves, use
    # this:
    nodes = {
      pizza = config.flake.nixosConfigurations.pizza.config;
      norte = config.flake.nixosConfigurations.norte.config;
    };
    # And this is for cases where we just want "the machine running
    # the X server".
    servers = {
      samba = nodes.norte;
      jellyfin = nodes.pizza;
      bitmagnet = nodes.pizza;
      radarr = nodes.norte;
      sonarr = nodes.norte;
      transmission = nodes.pizza;
    };
  };
}
