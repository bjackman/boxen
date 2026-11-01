# slopops, the agent that deploys the homelab, behind a chat page. See
# design_docs/slopops.md.
# It runs as the account slop-deploy.nix makes for deploys, which on pizza is
# the same one.
{
  config,
  lib,
  pkgs,
  homelab,
  ...
}:
let
  user = config.bjackman.slopDeploy.user;
  homePath = "/var/lib/slopops";
  deployHosts = builtins.attrNames (
    lib.filterAttrs (_: node: node.bjackman.slopDeploy.enable) homelab.nodes
  );
  claude = pkgs.bjackman.slopops.claudeConfig { prometheusUrl = "http://pizza:9090"; };
  probeClient = config.bjackman.slopClient.probeClient;
  slopDeploy = pkgs.writeShellScriptBin "slop-deploy" ''
    exec ${
      probeClient {
        sshUser = user;
        hosts = deployHosts;
        keyFile = config.age.secrets.slopops-ssh-privkey.path;
      }
    }/bin/slop-probe "$@"
  '';
  agentPath = [
    (probeClient { keyFile = config.age.secrets.slopops-probe-ssh-privkey.path; })
    slopDeploy
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.gnugrep
    pkgs.jq
    pkgs.openssh
  ];
  chatUser = "brendan";
  mirrorPath = "${homePath}/boxen.git";
  gerrit = homelab.servers.gerrit;
  # Recorded in the mirror's config, so the agent's own fetches use it too.
  gerritSshCommand = lib.escapeShellArgs [
    "ssh"
    "-i"
    config.age.secrets.slopops-gerrit-ssh-privkey.path
    "-o"
    "IdentitiesOnly=yes"
    "-o"
    "StrictHostKeyChecking=accept-new"
  ];
  prepare = pkgs.writeShellApplication {
    name = "slopops-chat-prepare";
    runtimeInputs = with pkgs; [
      coreutils
      git
      openssh
    ];
    text = ''
      if [ ! -e ${mirrorPath} ]; then
          GIT_SSH_COMMAND=${lib.escapeShellArg gerritSshCommand} git clone --quiet --mirror \
              -c core.sshCommand=${lib.escapeShellArg gerritSshCommand} \
              ssh://slopbot@${gerrit.networking.hostName}:${toString gerrit.bjackman.gerritSshPort}/boxen ${mirrorPath}
      fi
      mkdir -p "$HOME/.claude"
      ln -sfn ${pkgs.writers.writeJSON "slopops-settings.json" claude.settings} "$HOME/.claude/settings.json"
      ln -sfn ${claude.instructions} "$HOME/.claude/CLAUDE.md"
    '';
  };
in
{
  imports = [
    ../iap.nix
    ../slop-client.nix
    ../slopops-chat.nix
  ];

  age.secrets =
    lib.mapAttrs
      (
        _: secret:
        secret
        // {
          mode = "400";
          owner = user;
        }
      )
      {
        slopops-ssh-privkey.file = ../../secrets/slopops-ssh-privkey.age;
        # Read-only probes need nothing of slopops' own, so it shares the coding
        # agents' key.
        slopops-probe-ssh-privkey.file = ../../secrets/slopbot-probe-ssh-privkey.age;
        # Only to fetch the mirror. It could upload changes as slopbot too, which
        # still have to get through review.
        slopops-gerrit-ssh-privkey.file = ../../secrets/slopbot-ssh-privkey.age;
        # The review bot's long-lived token.
        slopops-claude-env.file = ../../secrets/review-bot-claude-env.age;
      };

  users.users.${user} = {
    home = homePath;
    createHome = true;
  };
  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = homePath;
      inherit user;
      group = user;
      mode = "0700";
    }
  ];

  bjackman.slopopsChat = {
    enable = true;
    inherit user;
    allowedUser = chatUser;
    socketGroup = config.services.caddy.group;
    workingDirPath = mirrorPath;
    stateDirPath = "${homePath}/chat";
    inherit (claude) mcpServers;
    vapidSubject = config.bjackman.iap.services.slopops.url;
    path = agentPath;
  };

  systemd.services.slopops-chat = {
    after = [ "gerrit.service" ];
    serviceConfig = {
      ExecStartPre = lib.getExe prepare;
      EnvironmentFile = config.age.secrets.slopops-claude-env.path;
      MemoryMax = "1G";
      CPUQuota = "200%";
    };
  };

  bjackman.iap.services.slopops = {
    socketPath = config.bjackman.slopopsChat.socketPath;
    allowedUsers = [ chatUser ];
  };
}
