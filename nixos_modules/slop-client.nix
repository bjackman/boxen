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
  knownHostsFile = pkgs.writeText "slop-probe-known-hosts" (
    lib.concatMapStrings (host: "${host} ${hostKeys.${host}}\n") probeHosts
  );
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
    probeClient = lib.mkOption {
      type = with lib.types; functionTo package;
      readOnly = true;
      description = ''
        Builds slop-probe for the homelab's hosts, given the arguments that
        differ by caller, such as keyFile, so that another agent on the host
        can have one with its own credentials.
      '';
    };
  };

  config = {
    bjackman.slopClient.packages = {
      slop-tools = pkgs.bjackman.slop-tools.override (
        gerritArgs
        // {
          gerritUrl = gerrit.bjackman.iap.services.gerrit.url;
          passwordFile = config.age.secrets.slopbot-authelia-password.path;
        }
      );
      slop-probe = cfg.probeClient { keyFile = config.age.secrets.slopbot-probe-ssh-privkey.path; };
    };
    bjackman.slopClient.probeClient =
      args:
      pkgs.bjackman.slop-probe.override (
        {
          inherit knownHostsFile;
          hosts = probeHosts;
        }
        // args
      );

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
