{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Note that I suspect things are amiss here. I think it's wrong that we are
  # using the "confidential" client type for the CLI auth, instead it should be
  # configured with "public = true" instead of having a client secret. However,
  # when I tried to set that up, I found that it failed and looking in tcpdump
  # it seemed that even with Perses configured with device_code.client_secret =
  # "", it was setting a client_secret. It rather seems like the Perses server
  # leaks its client secret to the CLI? Perhaps Perses is broken here.
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
    # https://github.com/zitadel/oidc/issues/830#issuecomment-3775205814
    allow_multiple_auth_methods = true;
  };
  persesConfig = {
    security = {
      encryption_key_file = config.age.secrets.perses-encryption-key.path;
      # Site is hosted behind SSL, so set this, shrug.
      cookie.secure = true;
      enable_auth = true;
      authentication = {
        access_token_ttl = "24h";
        refresh_token_ttl = "30d";
        providers.oidc = [
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
    };
    # Originally we hard-coded a specific directory here then populated that
    # separately, reasoning that this way we can update the provisioned
    # resources without restart Perses. But no. Perses doesn't have inotify set
    # up.
    provisioning.folders = [ config.bjackman.perses.resourceConfigs ];
  };
in
{
  imports = [
    ../iap.nix
  ];

  options.bjackman.perses = {
    resources = lib.mkOption {
      type =
        with lib.types;
        listOf (submodule {
          # Allow arbitrary other fields, this is the Perses attribute spec we
          # don't care about thge details.
          freeformType = attrs;
          # Require these two core fields of the resource, since they'll be used
          # to construct the JSON filename (ensuring uniqueness).
          options = {
            kind = lib.mkOption {
              type = str;
              description = "Perses resource type";
              example = "Dashboard";
            };
            metadata = lib.mkOption {
              type = submodule {
                freeformType = attrs;
                options.name = lib.mkOption {
                  type = str;
                  description = "Perses resource name";
                };
              };
            };
          };
        });
      description = ''
        Perses resources to provision. Files are prefixed so that they are
        alphanumerically sorted according to the order in this list.

        Note this whole thing is pretty silly, it's a weird leftover from a few
        phases of experimentation with different ways to configure Perses.
        Defining the resources directly in Nix like this does kinda make sense
        for stuff that's global and coupled to the rest of the Nix code and
        pretty straightforward. For dashboards though, you probably just wanna
        edit the Cue code that's built and hard-coded into the resourceConfigs
        option alongside this option.
      '';
      default = [ ];
    };
    resourceConfigs = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "For convenience, an option to expose the built configuration";
      default =
        let
          # Build linkFarm args for each of the resources defined via the
          # resources option.
          nixResourceLinks = map (res: rec {
            name = "${res.kind}_${res.metadata.name}.json";
            path = pkgs.writers.writeJSON name res;
          }) config.bjackman.perses.resources;
          # Compile Cue code into a directory using the Perses CLI. This is
          # probably a dumb way to do this I dunno.
          # Ditto for the resources defined in Cue.
          cueResources = pkgs.stdenv.mkDerivation {
            name = "cue-resources";
            src = ./.;
            nativeBuildInputs = with pkgs; [
              cue
              perses
            ];
            buildPhase = ''
              export CUE_CACHE_DIR=$(pwd)/.cue-cache
              cd dashboards
              percli dac build -d .
            '';

            installPhase = ''
              mkdir -p $out

              # Copy the built artifacts from the 'built' subdirectory
              # Adjust '../built' if the 'built' dir is created inside 'dashboards'
              cp -r built/* $out/
            '';
          };
          # Empirically, if we just link the output of the above derivation
          # straight into the resulting linkFarm, percli apply doesn't seem to
          # recurse into it. So we just directly set up individual links to the
          # relevant resources.
          cueResourceLinks =
            map
              (name: {
                name = "${name}.yaml";
                path = "${cueResources}/${name}/${name}_output.yaml";
              })
              [
                "nodes"
                "restic"
                "air"
              ];
          # Apply a fiddly prefix to ensures correct ordering so that resources
          # can safely refer to each other (e.g., 00_GlobalRole...,
          # 01_GlobalRoleBinding...). 99 resources ought to be enough for
          # anyone.
          resources = lib.imap0 (i: res: rec {
            name = "${lib.strings.fixedWidthString 2 "0" (toString i)}_${res.name}";
            path = res.path;
          }) (nixResourceLinks ++ cueResourceLinks);
        in
        pkgs.linkFarm "perses-provisioning" resources;
    };
  };

  config = {
    bjackman.iap.services.perses = {
      port = 8097;
      oidc = {
        enable = true;
        inherit autheliaConfig;
      };
    };

    systemd.services.perses =
      let
        configFile = pkgs.writeText "perses-config.json" (builtins.toJSON persesConfig);
      in
      {
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

    # Define base resources for the overall Perses deployment.
    bjackman.perses.resources = [
      {
        kind = "GlobalRole";
        metadata.name = "admin";
        spec.permissions = [
          {
            actions = [ "*" ];
            scopes = [ "*" ];
          }
        ];
      }
      # Grant admin access using the role defined above.
      {
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
      }
      # Defining this here just coz I don't see a Cue helper for this,
      # probably doesn't belong here.
      {
        kind = "Project";
        metadata.name = "homelab";
        spec.display.name = "Homelab";
      }
      # The datasource is coupled to the rest of the Nix code so defining it
      # here makes sense.
      {
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
      }
    ];
  };
}
