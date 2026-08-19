{
  pkgs,
  lib,
  config,
  ...
}:
let
  port = config.bjackman.ports.gerrit.port;
  sshPort = config.bjackman.ports.gerrit-ssh.port;
  url = config.bjackman.iap.services.gerrit.url;
  fqdn = config.bjackman.iap.services.gerrit.fqdn;
in
{
  imports = [
    ./ports.nix
    ./iap.nix
    ./impermanence.nix
    ./gerrit-bootstrap.nix
  ];

  bjackman.ports = {
    gerrit = { };
    gerrit-ssh = { };
  };

  bjackman.iap.services.gerrit = {
    inherit port;
    forwardAuth = true;
    # slopbot too: reading a change's inline comments is REST-only, and
    # Authelia authenticates that with basic auth rather than a session, so the
    # agent needs no credential of Gerrit's own.
    allowedUsers = [
      "brendan"
      "slopbot"
    ];
  };

  services.gerrit = {
    enable = true;
    listenAddress = "127.0.0.1:${toString port}";
    # Baked into NoteDb records, so this can never change without orphaning
    # review metadata.
    serverId = "3f9a2c47-8e1b-4d6a-9c53-7b2e5a081d64";
    builtinPlugins = [
      "download-commands"
      "hooks"
      "replication"
    ];
    settings = {
      gerrit.canonicalWebUrl = "${url}/";
      auth = {
        # Same arrangement as miniflux: the proxy is the only thing that can
        # set this header, so what it says is who you are. Only safe while
        # Gerrit listens on loopback and Caddy is the sole way in.
        type = "HTTP";
        httpHeader = "Remote-User";
      };
      httpd.listenUrl = "proxy-http://127.0.0.1:${toString port}/";
      sshd.listenAddress = "*:${toString sshPort}";
      sendemail.enable = false;
      change.enableAttentionSet = true;
      receive.enableSignedPush = false;
    };
  };

  bjackman.gerritAgentRepos = [ "boxen" ];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ sshPort ];

  # The module runs Gerrit under DynamicUser, so its state is really in
  # /var/lib/private. That has to be persisted as a whole and at 0700, which
  # systemd insists on before it will use any DynamicUser state directory -
  # persisting only the gerrit subdirectory leaves the parent at 0755 and
  # breaks every such service on the box.
  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = "/var/lib/private";
      mode = "0700";
      user = "root";
      group = "root";
    }
  ];
}
