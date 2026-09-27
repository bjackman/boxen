{
  config,
  lib,
  pkgs,
  homelab,
  ...
}:
let
  cfg = config.bjackman.slopClient;
  gerrit = homelab.servers.gerrit;
  gerritArgs = {
    gerritHost = gerrit.networking.hostName;
    gerritPort = gerrit.bjackman.gerritSshPort;
    keyFile = config.age.secrets.slopbot-ssh-privkey.path;
  };
  hostKeys = import ../secrets/host-keys.nix;
  probeHosts = builtins.attrNames homelab.nodes;
in
{
  options.bjackman.slopClient = {
    user = lib.mkOption {
      type = lib.types.str;
      description = "User the agent runs as, who gets to read slopbot's credentials.";
    };
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
    };
  };

  config = {
    bjackman.slopClient.packages = {
      slop = pkgs.bjackman.slop.override gerritArgs;
      slop-tools = pkgs.bjackman.slop-tools.override (
        gerritArgs
        // {
          gerritUrl = gerrit.bjackman.iap.services.gerrit.url;
          passwordFile = config.age.secrets.slopbot-authelia-password.path;
        }
      );
      slop-probe = pkgs.bjackman.slop-probe.override {
        hosts = probeHosts;
        keyFile = config.age.secrets.slopbot-probe-ssh-privkey.path;
        knownHostsFile = pkgs.writeText "slop-probe-known-hosts" (
          lib.concatMapStrings (host: "${host} ${hostKeys.${host}}\n") probeHosts
        );
      };
    };

    age.secrets = lib.genAttrs [
      "slopbot-ssh-privkey"
      "slopbot-probe-ssh-privkey"
      "slopbot-authelia-password"
    ] (name: {
      file = ../secrets/${name}.age;
      mode = "400";
      owner = cfg.user;
    });
  };
}
