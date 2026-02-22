{
  config,
  lib,
  pkgs,
  jellarr,
  agenix,
  ...
}:
let
  # See Perses setup for a more commented version of this thing with respect to
  # the Nix magic coupling this with the IAP module.
  # See
  # https://www.authelia.com/integration/openid-connect/clients/jellyfin/#authelia
  # for an example from the Authelia docs that is the origin of the actual
  # Authelia setup, much of which I do not really understand.
  # I had to make 1 changes, maybe because that guide is out of date, not sure:
  # - Changed the redirect URI to /sso/OID/riedirect/authelia instead of /sso/OID/r/authelias
  autheliaConfig = {
    client_id = "brKOp-c.3xuSP6oYsy6C9GRm3_EgBv-x__alD2VUv89pw3u6J001zIkRtyxRgKGMf7-VH46G";
    client_name = "Jellyfin";
    # This must be the hashed version of your secret
    client_secret = "{{- fileContent \"${config.age.secrets.authelia-jellyfin-client-secret-hash.path}\" | trim }}";
    public = false;
    authorization_policy = "one_factor";
    require_pkce = true;
    pkce_challenge_method = "S256";
    redirect_uris = [
      "${config.bjackman.iap.services.jellyfin.url}/sso/OID/redirect/authelia"
    ];
    scopes = [
      "openid"
      "profile"
      "groups"
    ];
    response_types = [ "code" ];
    grant_types = [ "authorization_code" ];
    access_token_signed_response_alg = "none";
    userinfo_signed_response_alg = "none";
    token_endpoint_auth_method = "client_secret_post";
  };
in
{
  # Note this is just the generic parts of the config, individual machines will
  # need more specific configs.
  imports = [
    agenix.nixosModules.default
    jellarr.nixosModules.default
    ./impermanence.nix
    ./iap.nix
  ];

  options.bjackman.jellyfin.httpPort = lib.mkOption {
    type = lib.types.int;
    # Note if you change this then services.jellyfin.openFirewall won't work any
    # more.
    default = 8096;
  };

  config = {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    age.secrets.jellyfin-admin-password = {
      file = ../secrets/jellyfin-admin-password.age;
      mode = "440";
      group = "jellyfin";
    };
    age.secrets.jellarr-api-key.file = ../secrets/jellarr-api-key.age;
    age.secrets.jellarr-env.file = ../secrets/jellarr-env.age;
    services.jellarr = {
      enable = true;
      user = "jellyfin";
      group = "jellyfin";
      environmentFile = config.age.secrets.jellarr-env.path;
      bootstrap = {
        enable = true;
        apiKeyFile = config.age.secrets.jellarr-api-key.path;
      };
      config = {
        version = 1;
        base_url = "http://localhost:${builtins.toString config.bjackman.jellyfin.httpPort}";
        system.enableMetrics = true;
        startup.completeStartupWizard = true;
        users = [
          {
            name = "brendan";
            passwordFile = config.age.secrets.jellyfin-admin-password.path;
            policy.isAdministrator = true;
          }
        ];
        system.pluginRepositories = [
          {
            name = "Jellyfin SSO";
            url = "https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json";
            enabled = true;
          }
        ];
        plugins = [
          {
            # Matches the name in the plugin repository manifest
            name = "SSO Authentication";
            # Do not set the configuration, we will inject a fully custom XML
            # file so that we can put secrets into it.
          }
        ];
        # This is how the SSO plugin documents that you should inject the button
        # to log in via OIDC.
        branding = {
          loginDisclaimer = ''
            <form action="${config.bjackman.iap.services.jellyfin.url}/sso/OID/start/authelia">
              <button class="raised block emby-button button-submit">
                Sign in with SSO
              </button>
            </form>
          '';
          customCss = ''
            a.raised.emby-button {
              padding: 0.9em 1em;
              color: inherit !important;
            }

            .disclaimerContainer {
              display: block;
            }
          '';
        };
      };
    };

    # The Jellyfin SSO auth plugin doesn't support sensible secret management so
    # we need to treat its entire configuration file as a seceret. Note
    # installing this file clashes with Jellar and Jellyfin themselves, it may
    # be flaky.
    age.secrets.authelia-jellyfin-client-secret = {
      file = ../secrets/authelia/jellyfin-client-secret.age;
      mode = "440";
      group = config.systemd.services.jellyfin.serviceConfig.Group;
    };
    age.secrets.authelia-jellyfin-client-secret-hash = {
      file = ../secrets/authelia/jellyfin-client-secret-hash.age;
      mode = "440";
      # Note this is readable by _Authelia_.
      group = config.systemd.services.authelia-main.serviceConfig.Group;
    };
    systemd.services.jellyfin = {
      # We also can't just symlink the secret into the directory as Jellyfin
      # expects to be able to modify it. So we just splat it on during startup
      # and hope for the best.
      preStart = ''
        OIDC_SECRET=$(cat ${config.age.secrets.authelia-jellyfin-client-secret.path})
        cat <<EOF > /var/lib/jellyfin/plugins/configurations/SSO-Auth.xml
        <?xml version="1.0" encoding="utf-8"?>
        <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <SamlConfigs />
          <OidConfigs>
            <item>
              <key>
                <string>authelia</string>
              </key>
              <value>
                <PluginConfiguration>
                  <OidEndpoint>${config.bjackman.iap.autheliaUrl}</OidEndpoint>
                  <OidClientId>${autheliaConfig.client_id}</OidClientId>
                  <OidSecret>$OIDC_SECRET</OidSecret>
                  <Enabled>true</Enabled>
                  <EnableAuthorization>true</EnableAuthorization>
                  <EnableAllFolders>true</EnableAllFolders>
                  <EnabledFolders />
                  <AdminRoles>
                    <string>admin</string>
                  </AdminRoles>
                  <Roles>
                    <string>jellyfin-users</string>
                    <string>admin</string>
                  </Roles>
                  <EnableFolderRoles>false</EnableFolderRoles>
                  <EnableLiveTvRoles>false</EnableLiveTvRoles>
                  <EnableLiveTv>false</EnableLiveTv>
                  <EnableLiveTvManagement>false</EnableLiveTvManagement>
                  <LiveTvRoles />
                  <LiveTvManagementRoles />
                  <FolderRoleMappings />
                  <RoleClaim>groups</RoleClaim>
                  <OidScopes>
                    <string>groups</string>
                  </OidScopes>
                  <CanonicalLinks></CanonicalLinks>
                  <DisableHttps>false</DisableHttps>
                  <DoNotValidateEndpoints>false</DoNotValidateEndpoints>
                  <DoNotValidateIssuerName>false</DoNotValidateIssuerName>
                  <DisablePushedAuthorization>true</DisablePushedAuthorization>
                </PluginConfiguration>
              </value>
            </item>
          </OidConfigs>
        </PluginConfiguration>
        EOF
      '';
      restartTriggers = [ config.age.secrets.authelia-jellyfin-client-secret.path ];
    };

    bjackman.iap.services.jellyfin = {
      port = config.bjackman.jellyfin.httpPort;
      oidc = {
        enable = true;
        inherit autheliaConfig;
      };
    };

    # Ugh, after all the effort of switching to BTRFS I realised that you can't
    # really have a fully impermanent Jellyfin setup. The whole system is just too
    # stateful. Just persist that shit.
    bjackman.impermanence.extraPersistence.directories = [
      {
        directory = "/var/lib/jellyfin";
        mode = "0770";
        group = "jellyfin";
      }
    ];
  };
}
