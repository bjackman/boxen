{
  disko.devices = {
    disk = {
      main = {
        # TODO: Do I replace this with a UUID once I have one?
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "100M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              # Disko is not really documented but I believe this is effectively
              # setting the swap size.
              end = "-64G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            swap = {
              size = "100%";
              content = {
                type = "swap";
                discardPolicy = "both"; # I dunno
                # Resume from hibernate from this partition.
                resumeDevice = true;
              };
            };
          };
        };
      };
    };
  };
}