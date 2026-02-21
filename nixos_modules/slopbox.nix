{ config, microvm, ... }:
{
  imports = [
    ./brendan.nix
    ./common.nix
    ./server.nix
    microvm.nixosModules.microvm
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  security.sudo.wheelNeedsPassword = false;

  networking.hostName = "slopbox";

  # From https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/
  services.resolved.enable = true;
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.tempAddresses = "disabled";
  systemd.network.enable = true;
  systemd.network.networks."10-e" = {
    matchConfig.Name = "e*";
    # TODO: this is coupled with the host configuration. Maybe DHCP would be
    # better?
    addresses = [ { Address = "192.168.83.2/24"; } ];
    routes = [ { Gateway = "192.168.83.1"; } ];
  };
  networking.nameservers = [
    "8.8.8.8"
    "1.1.1.1"
  ];
  # Disable firewall for faster boot and less hassle;
  # we are behind a layer of NAT anyway.
  networking.firewall.enable = false;

  nix = {
    # Disable optimisation as this doesn't work with microvm's writable store
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

  microvm = {
    hypervisor = "cloud-hypervisor";
    vcpu = 8;
    mem = 4 * 1024; # MiB

    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
      {
        tag = "src";
        # TODO: Hmmm
        source = "/home/brendan/src/slop";
        mountPoint = "/mnt/src";
        proto = "virtiofs";
      }
    ];
    writableStoreOverlay = "/nix/.rw-store";
    volumes = [
      {
        image = "nix-store-overlay.img";
        mountPoint = config.microvm.writableStoreOverlay;
        size = 32 * 1024; # MB
      }
      {
        image = "var.img";
        mountPoint = "/var";
        size = 8192; # MB
      }
    ];
    interfaces = [
      {
        type = "tap";
        # TODO: This is also coupled with the host config (ID must match the
        # systemd-networkd config).
        id = "microvm-slop";
        mac = "02:00:00:00:00:01"; # Highly recommended to set a static MAC
      }
    ];
  };
}
