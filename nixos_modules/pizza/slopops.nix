# slopops, the agent that deploys the homelab, as a Remote Control session I
# talk to from claude.ai/code and behind a chat page. See design_docs/slopops.md.
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
  probeHosts = builtins.attrNames homelab.nodes;
  deployHosts = builtins.attrNames (
    lib.filterAttrs (_: node: node.bjackman.slopDeploy.enable) homelab.nodes
  );
  claude = pkgs.bjackman.slopops.claudeConfig {
    inherit probeHosts;
    prometheusUrl = "http://pizza:9090";
  };
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
in
{
  imports = [
    ../iap.nix
    ../remote-control.nix
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
        # The review bot's long-lived token. The chat runs the agent through
        # the SDK, which can use one; Remote Control can't.
        slopops-claude-env.file = ../../secrets/review-bot-claude-env.age;
      };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "slopops-login" ''
      exec sudo -u ${user} -H ${lib.getExe pkgs.llm-agents.claude-code} auth login
    '')
  ];

  # Logging in is interactive: slopops-login.
  bjackman.remoteControl.slopops = {
    description = "slopops, the deploy agent, over Remote Control";
    inherit user homePath;
    createUser = false;
    checkout = {
      path = "${homePath}/boxen.git";
      mirror = true;
      keyFilePath = config.age.secrets.slopops-gerrit-ssh-privkey.path;
    };
    setup = ''
      mkdir -p "$HOME/.claude"
      ln -sfn ${pkgs.writers.writeJSON "slopops-settings.json" claude.settings} "$HOME/.claude/settings.json"
      ln -sfn ${claude.instructions} "$HOME/.claude/CLAUDE.md"
    '';
    # Gives every session the deploy tool.
    claudeJson = { inherit (claude) mcpServers; };
    sessionName = "pizza: slopops";
    permissionMode = "default";
    after = [ "gerrit.service" ];
    # pizza deploys pizza, so a deploy that changes this unit would otherwise
    # restart the session that asked for it, mid-deploy.
    restartIfChanged = false;
    path = agentPath;
    memoryMax = "1G";
    cpuQuota = "200%";
  };

  bjackman.slopopsChat = {
    enable = true;
    inherit user;
    allowedUser = chatUser;
    socketGroup = config.services.caddy.group;
    workingDirPath = config.bjackman.remoteControl.slopops.checkout.path;
    stateDirPath = "${homePath}/chat";
    inherit (claude) mcpServers;
    vapidSubject = config.bjackman.iap.services.slopops.url;
    path = agentPath;
  };

  systemd.services.slopops-remote-control.serviceConfig = import ../slopops-sandbox.nix;

  systemd.services.slopops-chat = {
    after = [ "gerrit.service" ];
    # As for the Remote Control session.
    restartIfChanged = false;
    serviceConfig = {
      # The Remote Control session's: the mirror, and ~/.claude.
      inherit (config.systemd.services.slopops-remote-control.serviceConfig) ExecStartPre;
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
