{ microvm, self, ... }:
{
  imports = [ microvm.nixosModules.host ];

  microvm.vms.slopbox = {
    evaluatedConfig = self.nixosConfigurations.slopbox;
    restartIfChanged = true;
  };

  systemd.network = {
    # Note it's OK to have this enabled as well as NetworkManager, as long as
    # they don't overlap on the interfaces they manage.
    enable = true;

    netdevs."20-microbr".netdevConfig = {
      Kind = "bridge";
      Name = "microbr";
    };

    networks = {
      "20-microbr" = {
        matchConfig.Name = "microbr";
        addresses = [ { Address = "192.168.83.1/24"; } ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
        };
      };
      "21-microvm-tap" = {
        matchConfig.Name = "microvm*";
        networkConfig.Bridge = "microbr";
      };
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ "microbr" ];
  };
}
