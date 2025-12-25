{ config, agenix, ... }:
{
  imports = [
    agenix.nixosModules.default
  ];

  # Can connect to this locally over HTTPS if I bypass my browser's complaint
  # that the CA is unknown.
  services.caddy = {
    enable = true;
    virtualHosts."localhost".extraConfig = ''
      respond "Hello, world!"
    '';
  };

  age.secrets =
    let
      mkSecret = name: {
        file = ../secrets/authelia + "/${name}.age";
        mode = "440";
        group = config.services.authelia.instances.main.group;
      };
    in
    {
      authelia-jwt-secret = mkSecret "jwt-secret";
      authelia-storage-encryption-key = mkSecret "storage-encryption-key";
      authelia-session-secret = mkSecret "session-secret";
    };

  services.authelia.instances.main = with config.age.secrets; {
    enable = true;

    secrets = with config.age.secrets; {
      jwtSecretFile = authelia-jwt-secret.path;
      storageEncryptionKeyFile = authelia-storage-encryption-key.path;
      sessionSecretFile = authelia-session-secret.path;
    };

    settings = {
      # server.address = "tcp://127.0.0.1:9091";
      # log.level = "debug";

      authentication_backend.file.path = "/var/lib/authelia/users.yml";

      storage.local.path = "/var/lib/authelia/db.sqlite3";

      # access_control.default_policy = "deny";
      # access_control.rules = [
      #   {
      #     domain = ["auth.example.com"];
      #     policy = "bypass";
      #   }
      # ];

      # session = {
      #   name = "authelia_session";
      #   domain = "example.com";
      #   expiration = 3600;
      #   inactivity = 300;
      # };

      # notifier.filesystem.filename = "/var/lib/authelia/notification.txt";
    };
  };
}
