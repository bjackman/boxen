{
  pkgs,
  lib,
  config,
  agenix,
  ...
}:
let
  autheliaPort = 9091;
  fileBrowserPort = config.services.filebrowser.settings.port;
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

      # Proxy FileBrowser, behind Authelia auth.
      # Gemini generated this and seems to have been cribbing from
      # https://www.authelia.com/integration/proxies/caddy/. As per that doc
      # this corresponds to the default configuration of Authelia's ForwardAuth
      # Authz implementation.
      # This makes a query to Authelia to get the auth state. If not
      # authenticated it redirects to the Authelia UI. If authenticated, it adds
      # the Remote-* headers to the request and forward it to the app.
      # It's important that all the headers that are of security relevance are
      # included here, so that if the user sets them in their own request, that
      # doesn't get forwarded directly to the app (allowing users to spoof
      # stuff).
      "filebrowser.app.localhost".extraConfig = ''
        forward_auth 127.0.0.1:${builtins.toString autheliaPort} {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
        reverse_proxy 127.0.0.1:${builtins.toString fileBrowserPort}
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
            domain = [ "filebrowser.app.localhost" ];
            policy = "one_factor";
          }
        ];
      };

      session = {
        name = "filebrowser_session";
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

  services.filebrowser = {
    enable = true;
    settings = {
      signup = false;
      # This tells FileBrowser to trust headers from our proxy.
      # Here FileBrowser is trusting the network. Anyone who can connect
      # directly to it, can spoof arbitrary users by manually setting the
      # Remote-User header.
      auth.method = "proxy";
      auth.header = "Remote-User";
      # Since we're effectively trusting the network it's important to only
      # listen for local connections.
      address = "localhost";
    };
  };
  system.activationScripts.filebrowser-users = {
    deps = [
      "users"
      "groups"
    ];
    text =
      let
        filebrowser = lib.getExe config.services.filebrowser.package;
        dbPath = config.services.filebrowser.settings.database;
        filebrowserUser = config.services.filebrowser.user;
        # TODO: Configure this
        users = [ "brendan" ];
        userListFile = pkgs.writeText "filebrowser-user-list.txt" (lib.concatStringsSep "\n" users);
      in
      ''
        set -eu
        
        # Manually ensure the directory exists because tmpfiles hasn't run yet.
        mkdir -p /var/lib/filebrowser
        chown filebrowser:filebrowser /var/lib/filebrowser
        chmod 0750 /var/lib/filebrowser

        # Ensure directory exists.
        if [ ! -f "${dbPath}" ]; then
          echo "Creating FileBrowser database at ${dbPath}"
          ${filebrowser} -d ${dbPath} config init
          chown ${filebrowserUser}:${filebrowserUser} "${dbPath}"
        fi

        while read -r user; do
          if ! ${filebrowser} -d ${dbPath} users find "$user"; then
            echo "Provisioning FileBrowser user: $user"
            # TODO: Make admin conditional
            ${filebrowser} -d ${dbPath} users add "$user" "dummy-unused-password" --perm.admin=true
          else
            echo "FileBrowser user $user already exists"
          fi
        done < "${userListFile}"
      '';
  };
}
