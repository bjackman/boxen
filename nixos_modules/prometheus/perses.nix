{
  pkgs,
  lib,
  config,
  ...
}:
let
  autheliaConfig = {
    # Not really clear why but docs say to use a random string here.
    # nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986
    client_id = "4guwUub8JViSDX~HIjtshmlnStejSe-tL5g.IqyqHm1CTJz2lVekSkCKiwczqxG645bucmFE";
    client_name = "Perses";
    # Note this is assuming that the "File Filters" feature is enabled:
    # https://www.authelia.com/configuration/methods/files/#file-filters
    # Note the client_secret is set separately via an environment
    # variable. (Most of the other secrets neeeded by Authelia are done via
    client_secret = "{{- fileContent \"${config.age.secrets.authelia-perses-client-secret-hash.path}\" | trim }}";
    authorization_policy = "one_factor";
    redirect_uris = [
      # IIUC the path here is coupled with Perses itself, this has to
      # match something set by Perses in a request it makes in the OIDC
      # flow. "authelia" is the "slug" used by Perses' auth config.
      "${config.bjackman.iap.services.perses.url}/api/auth/providers/oidc/authelia/callback"
    ];
    # No fuckin idea what this is but without it there's an error when
    # redirecting from Authelia back to Perses after the user approves
    # the auth.
    token_endpoint_auth_method = "client_secret_basic";
    # This is needed to make the "Device Authorization Flow" work - this
    # is how the "percli login" command works.
    grant_types = [
      "authorization_code"
      "refresh_token"
      "urn:ietf:params:oauth:grant-type:device_code"
    ];
    # Needed for offline_access, I don't fucken know lol.
    response_types = [ "code" ];
    scopes = [
      "openid"
      "profile"
      # Email is needed because (according to the AI that read the code) that's
      # the only user ID that Perses (0.53) actually takes from the OIDC
      # provider.
      "email"
      "offline_access"
    ];
  };
  persesConfig = {
    security = {
      encryption_key_file = config.age.secrets.perses-encryption-key.path;
      # Site is hosted behind SSL, so set this, shrug.
      cookie.secure = true;
      enable_auth = true;
      authentication.providers.oidc = [
        {
          slug_id = "authelia";
          name = "Authelia";
          client_id = autheliaConfig.client_id;
          client_secret_file = config.age.secrets.authelia-perses-client-secret.path;
          # This is something that services need to know in order to be able to
          # accept Authelia as a source of OIDC auth. I'm not 100% sure exactly
          # what it "means" and to be honest I'm not really sure where Authelia
          # derives this from.  Anyway, AI tells me that we do want this to be
          # the SSL URL and not just a localhost thingy.
          issuer = config.bjackman.iap.autheliaUrl;
          redirect_uri = "${config.bjackman.iap.services.perses.url}/api/auth/providers/oidc/authelia/callback";
          scopes = autheliaConfig.scopes;
        }
      ];
    };
    # Hard-code a specific directory for this rather than putting a store path
    # into the config directly - this means we can update the provisioned
    # resources. We then populate this directory separately.
    provisioning.folders = [ "/etc/perses/resources" ];
  };
in
{
  imports = [
    ../iap.nix
  ];

  config = {
    bjackman.iap.services.perses = {
      port = 8097;
      oidc = {
        enable = true;
        inherit autheliaConfig;
      };
    };

    # Delete the overlay below.
    warnings = lib.optional (
      let
        pkgsVersion = pkgs.filebrowser.version;
        myVersion = config.services.filebrowser.package.version;
      in
      lib.versionAtLeast pkgsVersion myVersion
    ) "Nixpkgs has caught up to pinned Perses version";

    # Need very latest version to get 76bcf7ca8699 (adds client_secret_file).
    # (This is actually already in the tip of 25.11 but hasn't been released yet).
    # Also pull in my slop fix for https://github.com/zitadel/oidc/issues/830
    nixpkgs.overlays = [
      (final: prev: {
        perses = prev.perses.overrideAttrs (old: rec {
          version = "0.53.0-client-secret-fix.8";

          src = final.fetchFromGitHub {
            # OK so in fact we need a fix for
            # https://github.com/zitadel/oidc/issues/830 too so this is a fork
            # with some slop in it.
            owner = "bjackman";
            repo = "perses";
            tag = "v${version}";
            hash = "sha256-S5bwCbAOUDKA4XayX/6NogjWuJEd4rVah46Y59Smx2U=";
          };

          vendorHash = "sha256-oR9KL+gJxxy/VKYVYechaBA+zrn9Wjh6dZPEKLYXm7o=";

          npmDeps = final.fetchNpmDeps {
            inherit (final.perses) src version;
            pname = "${old.pname}-ui";
            sourceRoot = "source/${old.npmRoot}";
            hash = "sha256-mHmadLRY9FwfaIbXLpfLXzrIbf6hUPi71jZ3hipoIUE=";
          };
        });
      })
    ];

    environment.systemPackages = [ pkgs.perses ];

    systemd.services.perses = {
      # We're gonna wait for the service to appear on the network anyway but as a
      # hack to avoid doing that unnecessarily we take advantage of the assumption
      # that it's on the same host.
      after = [ "authelia-main.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Perses crashes on startup if the OIDC provider isn't available.
        ExecStartPre =
          let
            url = "${config.bjackman.iap.autheliaUrl}/.well-known/openid-configuration";
            checkScript = pkgs.writeShellScript "wait-for-authelia" ''
              until ${pkgs.curl}/bin/curl -s --fail --max-time 5 "${url}"; do
                echo "Authelia not ready, waiting..."
                ${pkgs.coreutils}/bin/sleep 2
              done
            '';
          in
          "${checkScript}";
        ExecStart =
          let
            configFile = pkgs.writeText "perses-config.json" (builtins.toJSON persesConfig);
            listenAddr = "127.0.0.1:${toString config.bjackman.iap.services.perses.port}";
          in
          "${pkgs.perses}/bin/perses --config ${configFile} --web.listen-address ${listenAddr}";
        Restart = "always";
        User = "perses";
        Group = "perses";

        RuntimeDirectory = "perses";
        StateDirectory = "perses";
        WorkingDirectory = "/var/lib/perses";

        ProtectSystem = "full";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        RestrictRealtime = true;
        BindReadOnlyPaths = [
          config.age.secrets.perses-encryption-key.path
          config.age.secrets.authelia-perses-client-secret.path
          "/etc/resolv.conf"
          "/etc/hosts"
          "/etc/ssl/certs/ca-bundle.crt"
          "/etc/ssl/certs/ca-certificates.crt"
          "/etc/perses"
        ];
      };

      confinement.enable = true;
    };
    users.users.perses = {
      isSystemUser = true;
      group = "perses";
    };
    users.groups.perses = { };

    age.secrets = {
      perses-encryption-key = {
        file = ../../secrets/perses-encryption-key.age;
        mode = "440";
        group = config.systemd.services.perses.serviceConfig.Group;
      };
      authelia-perses-client-secret = {
        file = ../../secrets/authelia/perses-client-secret.age;
        mode = "440";
        group = config.systemd.services.perses.serviceConfig.Group;
      };
      authelia-perses-client-secret-hash = {
        file = ../../secrets/authelia/perses-client-secret-hash.age;
        mode = "440";
        # Note this is readable by _Authelia_.
        group = config.systemd.services.authelia-main.serviceConfig.Group;
      };
    };

    environment.etc."perses/resources".source = pkgs.linkFarm "perses-provisioning" [
      # Define the admin role.
      {
        name = "admin-role.json";
        path = pkgs.writers.writeJSON "admin-role.json" {
          kind = "GlobalRole";
          metadata.name = "admin";
          spec.permissions = [
            {
              actions = [ "*" ];
              scopes = [ "*" ];
            }
          ];
        };
      }
      # Grant admin access using the role defined above.
      {
        name = "admin-binding.json";
        path = pkgs.writers.writeJSON "admin-binding.json" {
          kind = "GlobalRoleBinding";
          metadata.name = "brendan-admin-binding";
          spec = {
            # TODO: Perses doesn't yet support binding to OIDC groups so just
            # directly configuring a user for now.
            role = "admin";
            subjects = [
              {
                kind = "User";
                # Perses uses the username part of the email to identify users, shrug.
                name = "bhenryj0117";
              }
            ];
          };
        };
      }
      # Defining this here just coz I don't see a Cue helper for this,
      # probably doesn't belong here.
      {
        name = "project-homelab.json";
        path = pkgs.writers.writeJSON "project-homelab.json" {
          kind = "Project";
          metadata.name = "homelab";
          spec.display.name = "Homelab";
        };
      }
      # The datasource is coupled to the rest of the Nix code so defining it
      # here makes sense.
      {
        name = "datasource-prometheus.json";
        path = pkgs.writers.writeJSON "datasource-prometheus.json" {
          kind = "GlobalDatasource";
          metadata.name = "prometheus";
          spec = {
            display.name = "Prometheus";
            default = true;
            plugin = {
              kind = "PrometheusDatasource";
              spec = {
                # The proxy configuration belongs inside the plugin's spec
                proxy = {
                  kind = "HTTPProxy";
                  spec.url = "http://127.0.0.1:${builtins.toString config.bjackman.iap.services.prometheus.port}";
                };
              };
            };
          };
        };
      }
    ];
  };
}
