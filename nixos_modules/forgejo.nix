{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.forgejo;
  port = config.bjackman.ports.forgejo.port;
  sshPort = config.bjackman.ports.forgejo-ssh.port;
  url = config.bjackman.iap.services.forgejo.url;
  fqdn = config.bjackman.iap.services.forgejo.fqdn;
  # Slug for the login source, appears in the "Sign in with ..." button and in
  # the redirect URI.
  oidcSlug = "authelia";
  autheliaConfig = {
    # nix run nixpkgs#authelia -- crypto rand --length 72 --charset rfc3986
    client_id = "kqiXXUmB8tQ1WZAYYoTqjTANVghNh4p3yFBAZSN86U.Ul-L0u7x.z519SwsWZCkBNUWqGe8D";
    client_name = "Forgejo";
    client_secret = "{{- fileContent \"${config.age.secrets.authelia-forgejo-client-secret-hash.path}\" | trim }}";
    public = false;
    authorization_policy = "one_factor";
    require_pkce = true;
    pkce_challenge_method = "S256";
    redirect_uris = [ "${url}/user/oauth2/${oidcSlug}/callback" ];
    scopes = [
      "openid"
      "profile"
      "email"
      "groups"
    ];
    response_types = [ "code" ];
    grant_types = [ "authorization_code" ];
    token_endpoint_auth_method = "client_secret_basic";
  };
in
{
  imports = [
    ./ports.nix
    ./iap.nix
    ./postgres.nix
    ./impermanence.nix
    ./forgejo-github-mirror.nix
  ];

  bjackman.ports = {
    forgejo = { };
    forgejo-ssh = { };
  };

  bjackman.iap.services.forgejo = {
    port = port;
    oidc = {
      enable = true;
      inherit autheliaConfig;
    };
    # No forward_auth, unlike everything else behind the IAP: API clients and
    # git-over-HTTP can't follow Authelia's login redirect, and both are needed
    # from outside pizza. Forgejo authenticates every request itself and trusts
    # no headers, so the exposed surface is the same one Codeberg runs.
    # See design_docs/agent_prs.md.
  };

  services.forgejo = {
    enable = true;
    # Not the module's default of forgejo-lts: the LTS is still on 15, which
    # doesn't support preferred_username below.
    package = pkgs.forgejo;
    database.type = "postgres";
    settings = {
      server = {
        DOMAIN = fqdn;
        ROOT_URL = "${url}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = port;
        # Git access is over SSH. Forgejo's own server rather than the host's
        # sshd: the alternative coupling is an AuthorizedKeysCommand in the
        # sshd that I use to fix this machine when it breaks.
        START_SSH_SERVER = true;
        SSH_DOMAIN = config.networking.hostName;
        SSH_PORT = sshPort;
        SSH_LISTEN_PORT = sshPort;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        ENABLE_INTERNAL_SIGNIN = false;
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        # Users predating this (i.e. one created by `forgejo admin user
        # create`) get linked to their OIDC identity by email.
        ACCOUNT_LINKING = "auto";
        USERNAME = "preferred_username";
      };
      repository.DEFAULT_BRANCH = "master";
      session = {
        # nixpkgs derives this from PROTOCOL, which is http because Caddy
        # terminates TLS - but the site is only ever reached over https.
        COOKIE_SECURE = true;
        # nixpkgs calls this "session", which any other service under
        # *.home.yawn.io can also claim on the parent domain. Two cookies of
        # one name arrive in one header and the wrong one wins, which breaks
        # the OIDC callback with "could not find a matching session".
        COOKIE_NAME = "forgejo_session";
      };
    };
  };

  age.secrets = {
    authelia-forgejo-client-secret = {
      file = ../secrets/authelia/forgejo-client-secret.age;
      mode = "440";
      group = config.services.forgejo.group;
    };
    authelia-forgejo-client-secret-hash = {
      file = ../secrets/authelia/forgejo-client-secret-hash.age;
      mode = "440";
      group = config.services.authelia.instances.main.group;
    };
  };

  # The nixpkgs module builds app.ini under a tmpfiles-created
  # stateDir/custom/conf. That works at boot, where the persistence bind mount
  # is up before systemd-tmpfiles-setup, but not on the switch that first
  # persists stateDir: there switch-to-configuration re-runs tmpfiles as part of
  # sysinit-reactivation.target, in an earlier batch than it starts new mounts,
  # so the rules land on the rootfs and the mount then hides them. Ordering
  # tmpfiles after the mount doesn't help - it isn't in that transaction.
  # Re-apply just this prefix once the mount is definitely there.
  systemd.services.forgejo-dirs = {
    requires = [ "var-lib-forgejo.mount" ];
    after = [ "var-lib-forgejo.mount" ];
    requiredBy = [ "forgejo-secrets.service" ];
    before = [ "forgejo-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=${cfg.stateDir}";
    };
  };

  # Forgejo keeps login sources in its database and there's no app.ini
  # equivalent, so this is the one part of the setup that has to be poked in at
  # runtime.
  systemd.services.forgejo-oidc = {
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    wantedBy = [ "multi-user.target" ];
    # The auth source embeds the client secret, so re-run when it changes.
    restartTriggers = [ config.age.secrets.authelia-forgejo-client-secret.file ];
    path = [
      cfg.package
      pkgs.gawk
    ];
    environment = {
      HOME = cfg.stateDir;
      FORGEJO_WORK_DIR = cfg.stateDir;
      FORGEJO_CUSTOM = cfg.customDir;
    };
    script = ''
      args=(
        --name ${oidcSlug}
        --provider openidConnect
        --key ${lib.escapeShellArg autheliaConfig.client_id}
        --secret "$(cat ${config.age.secrets.authelia-forgejo-client-secret.path})"
        --auto-discover-url ${config.bjackman.iap.autheliaUrl}/.well-known/openid-configuration
        --scopes ${lib.concatStringsSep " --scopes " autheliaConfig.scopes}
        # Admin rights follow from Authelia group membership, so the first
        # login doesn't need bootstrapping by hand.
        --group-claim-name groups
        --admin-group admin
      )
      id=$(forgejo admin auth list | awk '$2 == "${oidcSlug}" { print $1 }')
      if [ -n "$id" ]; then
        forgejo admin auth update-oauth --id "$id" "''${args[@]}"
      else
        forgejo admin auth add-oauth "''${args[@]}"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = cfg.user;
      Group = cfg.group;
      WorkingDirectory = cfg.stateDir;
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ sshPort ];

  # Note there are no backups: the GitHub mirror is the copy of record, so a
  # repo missing from this list has no backup at all. See design_docs/forgejo.md.
  bjackman.forgejoGithubMirrors = [ "boxen" ];

  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = cfg.stateDir;
      mode = "0750";
      user = cfg.user;
      group = cfg.group;
    }
  ];
}
