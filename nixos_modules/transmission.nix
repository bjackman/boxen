{
  pkgs,
  config,
  agenix,
  ...
}:
{
  imports = [
    ./brendan.nix
    agenix.nixosModules.default
  ];

  age.secrets.transmission-rpc-password-json.file = ../secrets/transmission-rpc-password.json.age;
  services.transmission = {
    package = pkgs.transmission_4;
    enable = true;
    openRPCPort = true;
    settings = {
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      rpc-authentication-required = true;
      rpc-username = "brendan";
    };
    # This is a weird roundabout way to set rpc-password in the the settings.
    # The name of the option is bad, it's actually a JSON file that gets merged
    # with the settings above.
    credentialsFile = config.age.secrets.transmission-rpc-password-json.path;
  };
  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = "/var/lib/transmission";
      mode = "0755";
    }
  ];
}
