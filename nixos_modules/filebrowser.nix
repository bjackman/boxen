{
  lib,
  pkgs,
  config,
  otherConfigs,
  ...
}:
{
  imports = [ ./iap.nix ];

  # Just delete the overrideAttrs block below.
  warnings = lib.optional (lib.versionAtLeast pkgs.filebrowser.version config.services.filebrowser.package.version) "Nixpkgs has caught up to pinned FileBrowser version";

  # Note that AFAICS certain settings can't be set in the --config file (i.e.
  # via services.filebrowser.settings):
  # https://github.com/filebrowser/filebrowser/pull/5643/files
  services.filebrowser = {
    enable = true;
    # This service is really annoying and fiddly and produces bad error
    # messages, and also seems buggy. I dunno if this version actually fixes any
    # bugs that I am affected by but just to try and eliminate potential causes
    # for confusion, use the latest version.
    package = pkgs.filebrowser.overrideAttrs (
      final: prev: rec {
        version = "2.53.0";
        src = pkgs.fetchFromGitHub {
          owner = "filebrowser";
          repo = "filebrowser";
          rev = "v${version}";
          hash = "sha256-ln7Dst+sN99c3snPU7DrIGpwKBz/e4Lz+uOknmm6sxg=";
        };
      }
    );
  };
  # Since we're doing a custom preStart, ensure the relevant directories exists.
  systemd.tmpfiles.settings."10-filebrowser" = {
    "${builtins.dirOf config.services.filebrowser.settings.database}" = {
      d = {
        mode = "0750";
        user = config.services.filebrowser.user;
        group = config.services.filebrowser.group;
      };
    };
  };
  # Configure users for filebrowser. I guess it would be nicer to do this with
  # an activationScript, but this doesn't work if the service is already
  # running, due to the database being constantly locked.
  systemd.services.filebrowser = {
    preStart =
      let
        dbPath = config.services.filebrowser.settings.database;
        filebrowser = "${lib.getExe config.services.filebrowser.package} -d ${dbPath}";
        serviceUser = config.services.filebrowser.user;
        users = config.bjackman.iap.users;
        mkUserCmds =
          u:
          let
            userArgs = lib.concatStringsSep " " [
              "--perm.admin=${lib.boolToString u.admin}"
              "--scope=${if u.admin then "." else "users/${u.name}"}"
              # FileBrowser password shouldn't matter anyway but to avoid confusion
              "--lockPassword"
            ];
          in
          ''
            if ! ${filebrowser} users find "${u.name}" >/dev/null; then
              echo "Provisioning FileBrowser user: ${u.name}"
              ${filebrowser} users add "${u.name}" "dummy-unused-password" ${userArgs}
            else
              echo "Updating FileBrowser user: ${u.name}"
              ${filebrowser} users update "${u.name}" ${userArgs}
            fi
          '';
        script = pkgs.writeShellScript "configure-filebrowser-db" ''
          if [ ! -f "${dbPath}" ]; then
            echo "Creating FileBrowser database at ${dbPath}"
            ${filebrowser} config init
            chown ${serviceUser}:${serviceUser} "${dbPath}"
          fi

          # So that the user setup operations below work against the correct root
          # dir, ensure that the root option is set in the DB as well as in the
          # --config that gets passed to the service at runtime.
          ${filebrowser} config set --root="${config.services.filebrowser.settings.root}"

          # These settings can only be set in the database.
          ${filebrowser} config set --signup=false
          # This tells FileBrowser to trust headers from our proxy.
          # Here FileBrowser is trusting the network. Anyone who can connect
          # directly to it, can spoof arbitrary users by manually setting the
          # Remote-User header.
          ${filebrowser} config set --auth.method=proxy --auth.header=Remote-User
          # Since we're effectively trusting the network it's important to only
          # listen for local connections.
          ${filebrowser} config set --address="localhost";

          # Inject the generated user provisioning logic
          ${lib.concatMapStringsSep "\n" mkUserCmds (lib.attrValues config.bjackman.homelab.users)}
        '';
      in
      "${script}";
    # Service can fail due to Samba issues so make sure it gets restarted.
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Wiki says this is required
  environment.systemPackages = [ pkgs.cifs-utils ];
  age.secrets.filebrowser-samba-password.file = ../secrets/filebrowser-samba-password.age;
  age-template.files.samba-creds = {
    vars.password = config.age.secrets.filebrowser-samba-password.path;
    content = ''
      username=${otherConfigs.sambaServer.bjackman.samba.users.filebrowser.name}
      password=$password
      domain=${otherConfigs.sambaServer.services.samba.settings.global.workgroup}
    '';
  };
  fileSystems."${config.services.filebrowser.settings.root}" = {
    # "nas" matches the share name in the server config
    device = otherConfigs.sambaServer.bjackman.samba.users.filebrowser.shareDevice;
    fsType = "cifs";
    options = [
      "x-systemd.automount"
      "noauto"
      "credentials=${config.age-template.files.samba-creds.path}"
      "nofail"
      # Local user that owns the files mounted here
      "uid=${config.services.filebrowser.user}"
      "gid=${config.services.filebrowser.group}"
    ];
  };

  bjackman.iap.services.filebrowser = {
    port = config.services.filebrowser.settings.port;
  };
}
