{
  pkgs,
  lib,
  config,
  agenix,
  agenix-template,
  homelabConfigs,
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
    ./derived-secrets.nix
    ./impermanence.nix
    ./users.nix
  ];

  options.bjackman.iap = {
    host = lib.mkOption {
      type = lib.types.bool;
      description = ''
        Whether this configuration hosts the proxy itself. This should only be
        set on one node. Other nodes can then import this module and define
        services without actually running the proxy.
      '';
      default = false;
    };
    services = lib.mkOption {
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
                  description = "Port the service exposes";
                };
                oidc = {
                  enable = lib.mkOption {
                    type = bool;
                    description = ''
                      Use OIDC instead of forward_auth.

                      Service is directly reverse-proxied by Caddy. Hopefully it
                      isn't trivially pwnable via its login page. It will then need
                      to be configured to do SSO via Authelia.
                    '';
                    default = false;
                  };
                  autheliaConfig = lib.mkOption {
                    type = attrs;
                    description = ''
                      Client configuration to add to Athelia's client list for
                      this service.

                      https://www.authelia.com/configuration/identity-providers/openid-connect/clients/
                    '';
                  };
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
      default = { };
    };
    autheliaUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.home.yawn.io";
      readOnly = true;
    };
  };

  config =
    let
      # Given a node configuration, produce a list of the service definitions
      # for that node. We also merge in a "host" attribute to each service
      # definition that identifies the host the service is on.
      # Note this assumes all of the homelabConfigs import the module so that
      # the bjackman.iap.services module exists.
      nodeServices =
        nodeConfig:
        lib.mapAttrsToList (
          name: service:
          # Hack: see if the hostname is the same as the current
          # configuration's hostname, if it is then use "localhost". Otherwise
          # we assume we can directly access the host by its name.
          let
            localHost = config.networking.hostName;
            remoteHost = nodeConfig.networking.hostName;
            host = if remoteHost == localHost then "localhost" else remoteHost;
          in
          service // { inherit host; }
        ) nodeConfig.bjackman.iap.services;
      allServices = lib.concatMap nodeServices (builtins.attrValues homelabConfigs);
    in
    lib.mkIf cfg.host {
      services.caddy = {
        enable = true;
        package = pkgs.caddy.withPlugins {
          plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
          hash = "sha256-SrAHzXhaT3XO3jypulUvlVHq8oiLVYmH3ibh3W3aXAs=";
        };
        # This configures Caddy to do the special dance with Cloudflare to get a
        # Lets Encrypt certificate. Because we want a wildcard certificate we need
        # to do the DNS-01 challenge, this supports that.
        globalConfig = ''
          debug
          acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}
        '';
        virtualHosts."*.${domain}, ${domain}".extraConfig = ''
          tls {
              dns cloudflare {$CLOUDFLARE_API_TOKEN}
          }

          # This is the Authelia UI. It doesn't get configured via
          # bjackman.iap.services since a) it shouldn't have a forward_auth rule
          # in Caddy and b) it shouldn't have an access control rule in Authelia.
          @auth host auth.${domain}
          handle @auth {
            reverse_proxy 127.0.0.1:${builtins.toString autheliaPort}
          }

          ${lib.concatStringsSep "\n" (
            builtins.map (service: ''
              @${service.subdomain} host ${service.subdomain}.${domain}
              handle @${service.subdomain} {
                ${lib.optionalString (!service.oidc.enable) ''
                  # Proxy this service with header-based authentication.  Gemini
                  # generated the actual config and seems to have been cribbing
                  # from https://www.authelia.com/integration/proxies/caddy/. As
                  # per that doc this corresponds to the default configuration of
                  # Authelia's ForwardAuth Authz implementation.
                  #
                  # This makes a query to Authelia to get the auth state. If not
                  # authenticated it redirects to the Authelia UI. If
                  # authenticated, it adds the Remote-* headers to the request and
                  # forward it to the app.
                  #
                  # It's important that all the headers that are of security
                  # relevance are included here, so that if the user sets them in
                  # their own request, that doesn't get forwarded directly to the
                  # app (allowing users to spoof stuff).
                  #
                  # To be honest, I do now know exactly how the redirection part
                  # happens, presumably Caddy does not know the URL of the
                  # Authelia UI, so I guess Authelia must somehow (via the cookie
                  # config...?) know that URL and inform Caddy about it.
                  forward_auth 127.0.0.1:${builtins.toString autheliaPort} {
                      uri /api/authz/forward-auth
                      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
                  }
                ''}
                reverse_proxy ${service.host}:${builtins.toString service.port}
              }
            '') allServices
          )}
        '';
      };
      bjackman.derived-secrets.envFiles.caddy.vars = {
        CLOUDFLARE_API_TOKEN = config.age.secrets.cloudflare-dns-api-token.path;
      };
      systemd.services.caddy.serviceConfig.EnvironmentFile = [
        config.bjackman.derived-secrets.envFiles.caddy.path
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
            rules = builtins.map (service: {
              domain = [ "${service.subdomain}.${domain}" ];
              # If using OIDC, disable the ForwardAuth middleware.
              policy = if service.oidc.enable then "bypass" else "one_factor";
            }) allServices;
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

          identity_providers.oidc.clients = lib.concatMap (
            s: lib.optional s.oidc.enable s.oidc.autheliaConfig
          ) allServices;

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
