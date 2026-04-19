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
  bjackman.ports.weather-risk = { };
  # Ensure it only uses local images to avoid accidentally falling back to
  # random services on remote registries.
  virtualisation.containers.registries.search = [ ];
  virtualisation.oci-containers.containers."weather-risk" = {
    image = "localhost/weather-risk:latest";
    pull = "never";
    ports = [ "${toString config.bjackman.ports.weather-risk.port}:80" ];
  };
}
