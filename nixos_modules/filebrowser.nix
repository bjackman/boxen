{
  lib,
  pkgs,
  config,
  otherConfigs,
  ...
}:
{
  imports = [
    ./iap.nix
    ./samba-client.nix
  ];

  # Note that AFAICS certain settings can't be set in the --config file (i.e.
  # via services.filebrowser.settings):
  # https://github.com/filebrowser/filebrowser/pull/5643/files
  services.filebrowser.enable = true;
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

  bjackman.sambaMounts.filebrowser = {
    passwordFile = ../secrets/filebrowser-samba-password.age;
    localUser = "filebrowser";
    localGroup = "filebrowser";
    mountpoint = config.services.filebrowser.settings.root;
  };

  bjackman.iap.services.filebrowser = {
    port = config.services.filebrowser.settings.port;
  };
}
