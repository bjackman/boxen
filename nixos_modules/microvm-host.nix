{ microvm, self, ... }:
{
  imports = [ microvm.nixosModules.host ];

  config.microvm.vms.slopbox.evaluatedConfig = self.nixosConfigurations.slopbox;
}
