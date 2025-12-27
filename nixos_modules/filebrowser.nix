{
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [ ./iap.nix ];

  # DON'T use the .settings field here. FileBrowser's configuration system is
  # extremely janky and pairs badly with the way nixpkgs sets this up. You can
  # only create users imperatively so we're gonna do that below in a preStart.
  # That requires us to also pre-create a database. When we do that we will
  # end up with settings in the database that override the settings passed via
  # --config which is what the nixpkgs setup does.
  services.filebrowser.enable = true;
  # Since we're doing a custom preStart, ensure the relevant directories exists.
  systemd.tmpfiles.settings."10-filebrowser" = {
    "/var/lib/filebrowser" = {
      d = {
        mode = "0750";
        user = config.services.filebrowser.user;
        group = config.services.filebrowser.group;
      };
    };
    "/var/lib/filebrowser/data" = {
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
      filebrowser = lib.getExe config.services.filebrowser.package;
      dbPath = config.services.filebrowser.settings.database;
      serviceUser = config.services.filebrowser.user;
      users = config.bjackman.iap.users;
      provisionUsersScript = lib.concatMapStrings (u: ''
        if ! ${filebrowser} -d ${dbPath} users find "${u.name}" >/dev/null; then
          echo "Provisioning FileBrowser user: ${u.name}"
          ${filebrowser} -d ${dbPath} users add "${u.name}" "dummy-unused-password" --perm.admin=${lib.boolToString u.admin}
        else
          echo "FileBrowser user ${u.name} already exists"
        fi
      '') users;
      script = pkgs.writeShellScript "provision-filebrowser-users" ''
        if [ ! -f "${dbPath}" ]; then
          echo "Creating FileBrowser database at ${dbPath}"
          ${filebrowser} -d ${dbPath} config init
          chown ${serviceUser}:${serviceUser} "${dbPath}"
        fi

        ${filebrowser} -d ${dbPath} config set --signup=false
        # This tells FileBrowser to trust headers from our proxy.
        # Here FileBrowser is trusting the network. Anyone who can connect
        # directly to it, can spoof arbitrary users by manually setting the
        # Remote-User header.
        ${filebrowser} -d ${dbPath} config set --auth.method=proxy --auth.header=Remote-User
        # Since we're effectively trusting the network it's important to only
        # listen for local connections.
        ${filebrowser} -d ${dbPath} config set --address="localhost";

        # Inject the generated user provisioning logic
        ${provisionUsersScript}
      '';
    in
    "${script}";
}
