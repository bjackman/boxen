{
  pkgs,
  lib,
  config,
  agenix,
  agenix-template,
  ...
}:
let
  autheliaPort = 9092;
  domain = "home.yawn.io";
  cfg = config.bjackman.iap;
in
{
  imports = [
    agenix.nixosModules.default
    agenix-template.nixosModules.default
    ./derived-secrets.nix
    ./impermanence.nix
    ./users.nix
  ];

  options.bjackman.iap.services = lib.mkOption {
    type =
      with lib.types;
      attrsOf (
        submodule (
          { config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = config._module.args.name;
                description = "Name of the service";
              };
              subdomain = lib.mkOption {
                type = lib.types.str;
                default = config._module.args.name;
                description = "Subdomain to proxy the service under";
              };
              port = lib.mkOption {
                type = lib.types.int;
                description = "Port the service exposes on localhost";
              };
              url = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                description = "URL where the service is available via the proxy";
                default = "https://${config.subdomain}.${domain}";
              };
            };
          }
        )
      );
  };

  config = {
    # Can connect to this locally over HTTPS if I bypass my browser's complaint
    # that the CA is unknown.
    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
        hash = "sha256-dnhEjopeA0UiI+XVYHYpsjcEI6Y1Hacbi28hVKYQURg=";
      };
      # This configures Caddy to do the special dance with Cloudflare to get a
      # Lets Encrypt certificate. Because we want a wildcard certificate we need
      # to do the DNS-01 challenge, this supports that.
      globalConfig = ''
        debug
        acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}
      '';
      virtualHosts = {
        # This block is supposed to a) tell the ACME logic that we want a
        # wildcard SSL cert and b) configure caddy to use that cert for all the
        # other matching blocks. It looks like in practice it just registered
        # separate certs for each domain as well, if I wanna use the wildcard
        # domain I think I have to restructure the config. I don't think I
        # actually care though.
        "${domain}, *.${domain}".extraConfig = ''
          tls {
              dns cloudflare {$CLOUDFLARE_API_TOKEN}
          }
        '';
        # This is the Authelia UI. It doesn't get configured via
        # bjackman.iap.services since a) it shouldn't have a forward_auth rule
        # in Caddy and b) it shouldn't have an access control rule in Authelia.
        "auth.${domain}".extraConfig = ''
          reverse_proxy 127.0.0.1:${builtins.toString autheliaPort}
        '';
      }
      // (lib.mapAttrs' (name: service: {
        name = "${service.subdomain}.${domain}";
        # Proxy services, behind Authelia auth.
        # Gemini generated the actual config and seems to have been cribbing
        # from https://www.authelia.com/integration/proxies/caddy/. As per that
        # doc this corresponds to the default configuration of Authelia's
        # ForwardAuth Authz implementation.
        # This makes a query to Authelia to get the auth state. If not
        # authenticated it redirects to the Authelia UI. If authenticated, it adds
        # the Remote-* headers to the request and forward it to the app.
        # It's important that all the headers that are of security relevance are
        # included here, so that if the user sets them in their own request, that
        # doesn't get forwarded directly to the app (allowing users to spoof
        # stuff).
        # To be honest, I do now know exactly how the redirection part happens,
        # presumably Caddy does not know the URL of the Authelia UI, so I guess
        # Authelia must somehow (via the cookie config...?) know that URL and
        # inform Caddy about it.
        value.extraConfig = ''
          forward_auth 127.0.0.1:${builtins.toString autheliaPort} {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
          }
          reverse_proxy 127.0.0.1:${builtins.toString service.port}
        '';
      }) cfg.services);
    };
    age-template.files."caddy.env" = {
      vars.token = config.age.secrets.cloudflare-dns-api-token.path;
      content = "CLOUDFLARE_API_TOKEN=$token";
    };
    systemd.services.caddy.serviceConfig.EnvironmentFile = [
      config.age-template.files."caddy.env".path
    ];
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

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
        authelia-passwords-json = mkSecret "passwords.json";
      };
    bjackman.derived-secrets.files."authelia_users.json" = {
      script = ''
        "${lib.getExe pkgs.jq}" -n \
          --argjson users ${lib.escapeShellArg (builtins.toJSON config.bjackman.homelab.users)} \
          --argjson passwords "$(cat "${config.age.secrets.authelia-passwords-json.path}")" \
          '{
            users: ($users | map({
              key: .name,
              value: {
                password: $passwords[.name],
                displayname: .displayName,
                email: "",
                groups: []
              }
            }) | from_entries)
          }'
      '';
      mode = "440";
      group = config.services.authelia.instances.main.group;
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
          # So we use a more fancy technique where the file is generated at
          # runtime.
          file.path = config.bjackman.derived-secrets.files."authelia_users.json".path;
        };

        storage.local.path = "/var/lib/authelia-main/db.sqlite3";

        access_control = {
          default_policy = "deny";
          rules = lib.mapAttrsToList (name: service: {
            domain = [ "${service.subdomain}.${domain}" ];
            policy = "one_factor";
          }) cfg.services;
        };

        session = {
          name = "session";
          cookies = [
            {
              domain = "${domain}";
              authelia_url = "https://auth.${domain}";
            }
          ];
        };

        # This is a dummy for sending email notifications. It's required for the
        # configuration to validate. I think for the way I've set this up (e.g. no
        # password reset flow), this is unused.
        notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";
      };
    };

    # Reload the service when the secret changes - since its path is fixed
    # (/run/agenix/authelia-passwords-json) changes to this won't actually change
    # the content of the Authelia config itself so we need to be explicit here.
    systemd.services."authelia-main".restartTriggers = [
      config.age.secrets.authelia-passwords-json.file
    ];

    # Actually only need to persist db.sqlite3 but having symlinks to individual
    # files like that is awkward with systemd sandboxing. So just persist the
    # whole directory.
    bjackman.impermanence.extraPersistence.directories = [
      {
        directory = "/var/lib/authelia-main";
        mode = "0700";
        user = "authelia-main";
        group = "authelia-main";
      }
    ];
  };
}
