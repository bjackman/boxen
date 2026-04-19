# This module runs a service from a local OCI image that is NOT configured in
# this repository. The idea here is to let me deploy it orthogonally to the
# overall homelab. With this configuration alone the service will fail to start
# because it won't find the image in its local daemon.
# To use it, build a container image, e.g. using
# pkgs.dockerTools.buildLayeredImage then load it into the Podman daemon using
# `sudo docker load < image.tgz`. (Note the sudo is important since it needs to
# be in the root user's database).
{ config, ... }:
{

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
    };
  };

  # THIS IS GARBAGE I DON'T FUCKING KNOW JUST DOING WHATEVER SLOP MAKES IT WORK
  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = "/var/lib/containers/storage/volumes";
      mode = "0711";
    }
    {
      directory = "/var/lib/containers/storage/overlay";
      mode = "0711";
    }
  ];
  systemd.network.networks."00-unmanaged-containers" = {
    matchConfig.Name = "veth* podman*";
    linkConfig.Unmanaged = "yes";
  };
  systemd.network.links."10-veth-mac" = {
    matchConfig.OriginalName = "veth*";
    linkConfig.MACAddressPolicy = "none";
  };

  bjackman.ports.weather-risk = { };
  networking.firewall.allowedTCPPorts = [ config.bjackman.ports.weather-risk.port ];
  # Ensure it only uses local images to avoid accidentally falling back to
  # random services on remote registries.
  virtualisation.containers.registries.search = [ ];
  virtualisation.oci-containers.containers."weather-risk" = {
    image = "localhost/weather-risk:latest";
    pull = "never";
    ports = [ "0.0.0.0:${toString config.bjackman.ports.weather-risk.port}:80" ];
  };
  networking.firewall.trustedInterfaces = [ "podman+" ];

  bjackman.iap.services.weather-risk.port = config.bjackman.ports.weather-risk.port;
}
