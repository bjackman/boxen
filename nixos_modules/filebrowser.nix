{
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [ ./iap.nix ];

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
  systemd.services.filebrowser.preStart =
    let
      dbPath = config.services.filebrowser.settings.database;
      filebrowser = "${lib.getExe config.services.filebrowser.package} -d ${dbPath}";
      serviceUser = config.services.filebrowser.user;
      users = config.bjackman.iap.users;
      provisionUsersScript = lib.concatMapStrings (u: ''
        if ! ${filebrowser} users find "${u.name}" >/dev/null; then
          echo "Provisioning FileBrowser user: ${u.name}"
          ${filebrowser} users add "${u.name}" "dummy-unused-password" --perm.admin=${lib.boolToString u.admin}
        else
          echo "FileBrowser user ${u.name} already exists"
        fi
      '') users;
      script = pkgs.writeShellScript "provision-filebrowser-users" ''
        if [ ! -f "${dbPath}" ]; then
          echo "Creating FileBrowser database at ${dbPath}"
          ${filebrowser} config init
          chown ${serviceUser}:${serviceUser} "${dbPath}"
        fi

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
        ${provisionUsersScript}
      '';
    in
    "${script}";
}
