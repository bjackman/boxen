{
  pkgs,
  lib,
  config,
  ...
}:
let
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
          # TODO: Avoid duping all these fields:
          client_id = "4guwUub8JViSDX~HIjtshmlnStejSe-tL5g.IqyqHm1CTJz2lVekSkCKiwczqxG645bucmFE";
          client_secret_file = config.age.secrets.authelia-perses-client-secret.path;
          issuer = "https://auth.home.yawn.io";
          redirect_uri = "https://perses.home.yawn.io/api/auth/providers/oidc/authelia/callback";
          scopes = [
            "openid"
            "profile"
            "email"
            "offline_access"
          ];
        }
      ];
    };
    provisioning.folders = [
      (pkgs.linkFarm "perses-provisioning" [
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
      ])
    ];
  };
in
{
  imports = [
    ../iap.nix
  ];

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
    # TODO Avoid coupling on name of service
    after = [ "authelia-main.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      # Perses crashes on startup if the OIDC provider isn't available.
      ExecStartPre =
        let
          checkScript = pkgs.writeShellScript "wait-for-authelia" ''
            until ${pkgs.curl}/bin/curl -s --fail --max-time 5 https://auth.home.yawn.io/.well-known/openid-configuration; do
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
      CapabilityBoundingSet = ""; # Removes all kernel capabilities
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
  };

  bjackman.iap.services.perses = {
    port = 8097;
    useOidc = true;
  };
}
