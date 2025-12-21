{ lib, disko, ... }:

{
  imports = [
    disko.nixosModules.disko
  ];

  # Copied from
  # https://michael.stapelberg.ch/posts/2025-06-01-nixos-installation-declarative/#nixos-anywhere
  # but with nvme0n1 instead of sda.
  disko.devices = {
    disk = {
      main = {
        device = lib.mkDefault "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                # Dunno what this does, but disko example sets it, Gemini says
                # "recommended for NVMe/SSDs".
                discardPolicy = "both";
                resumeDevice = false;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/persistent";
              };
            };
          };
        };
      };
    };
  };
}
