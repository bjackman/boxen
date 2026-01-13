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
                type = str;
                default = config._module.args.name;
                description = "Name of the service";
              };
              subdomain = lib.mkOption {
                type = str;
                default = config._module.args.name;
                description = "Subdomain to proxy the service under";
              };
              port = lib.mkOption {
                type = int;
                description = "Port the service exposes on localhost";
              };
              url = lib.mkOption {
                type = str;
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
        email bhenryj0117@gmail.com
        acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}
      '';
      # workaround. is a temporary hack to get certs from let's encrypt as suggested here:
      # https://letsencrypt.org/docs/rate-limits/#new-certificates-per-exact-set-of-identifiers
      virtualHosts."*.${domain}, ${domain}".extraConfig = ''
        tls {
            issuer acme {
              dir https://acme.zerossl.com/v2/DV90
              dns cloudflare {$CLOUDFLARE_API_TOKEN}
            }
        }

        # This is the Authelia UI. It doesn't get configured via
        # bjackman.iap.services since a) it shouldn't have a forward_auth rule
        # in Caddy and b) it shouldn't have an access control rule in Authelia.
        @auth host auth.${domain}
        handle @auth {
          reverse_proxy 127.0.0.1:${builtins.toString autheliaPort}
        }

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
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: service: ''
            @${service.subdomain} host ${service.subdomain}.${domain}
            handle @${service.subdomain} {
              forward_auth 127.0.0.1:${builtins.toString autheliaPort} {
                  uri /api/authz/forward-auth
                  copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 127.0.0.1:${builtins.toString service.port}
            }
          '') cfg.services
        )}
      '';
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
        authelia-hmac-secret = mkSecret "hmac-secret";
        authelia-oidc-privkey = mkSecret "oidc-priv.pem";
        authelia-perses-client-secret-hash = mkSecret "perses-client-secret-hash";
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
                email: .email,
                # Map the admin boolean to the "admin" group string
                groups: (if .admin then ["admin"] else [] end)
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
        oidcHmacSecretFile = authelia-hmac-secret.path;
        oidcIssuerPrivateKeyFile = authelia-oidc-privkey.path;
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

        identity_providers.oidc.clients = [
          # TODO: Avoid depending on Perses config here (optionize this).
          {
            # Not really clear why but docs say to use a random string here.
            # nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986
            client_id = "4guwUub8JViSDX~HIjtshmlnStejSe-tL5g.IqyqHm1CTJz2lVekSkCKiwczqxG645bucmFE";
            client_name = "Perses";
            # Note this is assuming that the "File Filters" feature is enabled:
            # https://www.authelia.com/configuration/methods/files/#file-filters
            # Note the client_secret is set separately via an environment
            # variable. (Most of the other secrets neeeded by Authelia are done via
            client_secret = ''{{- secret "${authelia-perses-client-secret-hash.path}" }}'';
            authorization_policy = "one_factor";
            redirect_uris = [
              # IIUC the path here is coupled with Perses itself, this has to
              # match something set by Perses in a request it makes in the OIDC
              # flow. "authelia" is the "slug" used by Perses' auth config.
              "${cfg.services.perses.url}/auth/providers/oidc/authelia/callback"
            ];
          }
        ];

        # This is a dummy for sending email notifications. It's required for the
        # configuration to validate. I think for the way I've set this up (e.g. no
        # password reset flow), this is unused.
        notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";
      };
    };

    systemd.services."authelia-main" = {
      # Reload the service when the secret changes - since its path is fixed
      # (/run/agenix/authelia-passwords-json) changes to this won't actually change
      # the content of the Authelia config itself so we need to be explicit here.
      restartTriggers = [
        config.age.secrets.authelia-passwords-json.file
      ];
      # https://www.authelia.com/configuration/methods/files/#file-filters
      environment.X_AUTHELIA_CONFIG_FILTERS = "template";
    };

    bjackman.impermanence.extraPersistence.directories = [
      # Actually only need to persist db.sqlite3 but having symlinks to individual
      # files like that is awkward with systemd sandboxing. So just persist the
      # whole directory.
      {
        directory = "/var/lib/authelia-main";
        mode = "0700";
        user = "authelia-main";
        group = "authelia-main";
      }
      # Persist certificates so we don't get rate-limited by Let's Encrypt.
      (
        let
          service = config.systemd.services.caddy.serviceConfig;
        in
        {
          directory = "/var/lib/caddy";
          mode = "0700";
          user = service.User;
        }
      )
    ];
  };
}
