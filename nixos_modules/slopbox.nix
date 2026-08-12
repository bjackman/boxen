{ config, modulesPath, ... }:
{
  imports = [
    ./brendan.nix
    ./common.nix
    ./server.nix
    "${modulesPath}/virtualisation/incus-virtual-machine.nix"
    # Note it's unusual to directly import brendan-home.nix from a host's
    # top-level module, usually they'll import pc.nix, but this is a VM.
    ./brendan-home.nix
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  security.sudo.wheelNeedsPassword = false;

  networking.hostName = "slopbox";

  # Disable firewall for faster boot and less hassle;
  # we are behind a layer of NAT anyway.
  networking.firewall.enable = false;

  nix = {
    # Disable optimisation as this doesn't work with a writable store
    # overlay.
    optimise.automatic = false;
  };

  # Generate SSH host keys at a location that persists between boots.
  services.openssh.hostKeys = [
    {
      path = "/var/slopbox/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  # I dunno what this does but without it I get an error when trying to use Home
  # Manager.
  # https://discourse.nixos.org/t/error-gdbus-error-org-freedesktop-dbus-error-serviceunknown-the-name-ca-desrt-dconf-was-not-provided-by-any-service-files/29111
  programs.dconf.enable = true;

  # We're gonna be building a disk image for this and it's really annoying to
  # invalidate that hash so don't include the config reviison.
  system.configurationRevision = null;

  boot.loader.timeout = 0;

  system.stateVersion = "25.11";
}
