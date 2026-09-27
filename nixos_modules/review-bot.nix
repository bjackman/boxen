{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.bjackman.reviewBot;
  stateDir = "/var/lib/review-bot";
  flags = lib.escapeShellArgs [
    "--gerrit-host=${config.networking.hostName}"
    "--gerrit-port=${toString config.bjackman.gerritSshPort}"
    "--key-file=${config.age.secrets.review-bot-ssh-privkey.path}"
    "--project=${cfg.project}"
    "--state-dir=${stateDir}"
  ];
in
{
  options.bjackman.reviewBot = {
    enable = lib.mkEnableOption "the review bot";
    project = lib.mkOption {
      type = lib.types.str;
      default = "boxen";
      description = "The one project whose changes are reviewed.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = lib.genAttrs [ "review-bot-ssh-privkey" "review-bot-claude-env" ] (name: {
      file = ../secrets/${name}.age;
      owner = "review-bot";
    });

    # Its own user rather than the agent's, so that the agent can't post as it
    # and the reviewer doesn't inherit the agent's instructions and memory.
    users.users.review-bot = {
      isSystemUser = true;
      group = "review-bot";
      home = stateDir;
    };
    users.groups.review-bot = { };

    systemd.services.review-bot = {
      after = [
        "gerrit.service"
        "gerrit-bootstrap.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.bjackman.review-bot}/bin/review-bot ${flags}";
        User = "review-bot";
        Group = "review-bot";
        EnvironmentFile = config.age.secrets.review-bot-claude-env.path;
        Restart = "always";
        RestartSec = 30;
        StateDirectory = "review-bot";
        # It shares the host with Gerrit's JVM and the CI runner.
        MemoryHigh = "1G";
        MemoryMax = "1500M";
        OOMPolicy = "continue";
        CPUQuota = "200%";
        Nice = 10;
      };
    };
  };
}
