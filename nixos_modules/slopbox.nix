{ config, microvm, ... }:
{
  imports = [
    ./brendan.nix
    ./common.nix
    microvm.nixosModules.microvm
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  security.sudo.wheelNeedsPassword = false;

  networking.hostName = "slopbox";

  microvm = {
    hypervisor = "cloud-hypervisor";
    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
    ];
    volumes = [
      {
        image = "nix-store-overlay.img";
        mountPoint = config.microvm.writableStoreOverlay;
        size = 2048;
      }
    ];
  };
}
