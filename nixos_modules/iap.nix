{
  pkgs,
  config,
  agenix,
  ...
}:
{
  imports = [
    agenix.nixosModules.default
  ];

  # Can connect to this locally over HTTPS if I bypass my browser's complaint
  # that the CA is unknown.
  services.caddy = {
    enable = true;
    virtualHosts = {
      # This is the authelia UI.
      "auth.app.localhost".extraConfig = ''
        reverse_proxy 127.0.0.1:9091
      '';

      # Dummy app that we'll configure to auth via Authelia.
      # TODO: Gemini generated this. Should read the docs to understand what
      # this actually does.
      "app.localhost".extraConfig = ''
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        respond "Authenticated!"
      '';
    };
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
      authelia-brendan-password-hash = mkSecret "brendan-password-hash";
      authelia-users-yaml = mkSecret "users.yaml";
    };

  services.authelia.instances.main = with config.age.secrets; {
    enable = true;

    # These options are higher-level functionality provided by the nixpkgs
    # packaging, this doesn't directly correspond to the Authelia secrets
    # system it just populates some other settings values in a nice way.
    secrets = with config.age.secrets; {
      jwtSecretFile = authelia-jwt-secret.path;
      storageEncryptionKeyFile = authelia-storage-encryption-key.path;
      sessionSecretFile = authelia-session-secret.path;
    };

    settings = {
      authentication_backend = {
        password_reset.disable = true;
        # Authelia has nice ways to read files/env vars and then do templating
        # on them. So you'd think we'd be able to define the users in Nix and
        # then just inject the password hashes as secrets. But, the user
        # config file is a kinda static resource that doesn't support that.
        # So whatever, just encrypt the whole config.
        file.path = authelia-users-yaml.path;
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = [ "app.localhost" ];
            policy = "one_factor";
          }
        ];
      };

      session = {
        name = "authelia_session";
        cookies = [
          {
            domain = "app.localhost";
            authelia_url = "https://auth.app.localhost";
          }
        ];
      };

      # This is a dummy for sending email notifications. It's required for the
      # configuration to validate. I think for the way I've set this up (e.g. no
      # password reset flow), this is unused.
      notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";
    };
  };
}
