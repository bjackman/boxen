# slopops, the agent that deploys the homelab, as a Remote Control session I
# talk to from claude.ai/code. See design_docs/slopops.md. It runs as the
# account slop-deploy.nix makes for deploys, which on pizza is the same one.
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
  claude = pkgs.bjackman.slopops.claudeConfig {
    inherit probeHosts;
    prometheusUrl = "http://pizza:9090";
  };
  probeClient = config.bjackman.slopClient.probeClient;
  slopDeploy = pkgs.writeShellScriptBin "slop-deploy" ''
    exec ${
      probeClient {
        sshUser = user;
        hosts = [ "pizza" ];
        keyFile = config.age.secrets.slopops-ssh-privkey.path;
      }
    }/bin/slop-probe "$@"
  '';
in
{
  imports = [
    ../remote-control.nix
    ../slop-client.nix
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
    path = [
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
    memoryMax = "1G";
    cpuQuota = "200%";
  };
}
