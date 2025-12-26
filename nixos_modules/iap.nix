{
  pkgs,
  config,
  agenix,
  ...
}:
let
  autheliaPort = 9091;
in
{
  imports = [
    agenix.nixosModules.default
    ./impermanence.nix
  ];

  # Can connect to this locally over HTTPS if I bypass my browser's complaint
  # that the CA is unknown.
  services.caddy = {
    enable = true;
    virtualHosts = {
      # This is the authelia UI.
      "auth.app.localhost".extraConfig = ''
        reverse_proxy 127.0.0.1:${builtins.toString autheliaPort}
      '';

      # Dummy app that we'll configure to auth via Authelia.
      # Gemini generated this and seems to have been cribbing from
      # https://www.authelia.com/integration/proxies/caddy/. As per that doc
      # this corresponds to the default configuration of Authelia's ForwardAuth
      # Authz implementation.
      # TO be honest there is a lot going on that I don't understand here, the
      # Authelia docs are not that clear.
      "app.localhost".extraConfig = ''
        forward_auth 127.0.0.1:${builtins.toString autheliaPort} {
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
      server.address = "tcp://:${builtins.toString autheliaPort}/";

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

  bjackman.impermanence.extraPersistence.files = [
    config.services.authelia.instances.main.settings.storage.local.path
  ];
}
