{ config, agenix, ... }:
{
  imports = [
    ./brendan.nix
    agenix.nixosModules.default
  ];

  assertions = [
    {
      assertion = config.services.openssh.settings.PasswordAuthentication == false;
      message = "Disable SSH password auth";
    }
  ];
  age.secrets.weak-local-password-hash.file = ../secrets/weak-local-password-hash.age;
  users.users.brendan.hashedPasswordFile = config.age.secrets.weak-local-password-hash.path;
}
