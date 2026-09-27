{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.bjackman.gerritCi;
  logPort = config.bjackman.ports.gerrit-ci-logs.port;
  logUrl = config.bjackman.iap.services.gerrit-ci-logs.url;
  stateDir = "/var/lib/gerrit-ci";
  keyFile = config.age.secrets.ci-bot-ssh-privkey.path;
  flags = lib.escapeShellArgs [
    "--gerrit-host=${config.networking.hostName}"
    "--gerrit-port=${toString config.bjackman.gerritSshPort}"
    "--key-file=${keyFile}"
    "--project=${cfg.project}"
    "--log-url=${logUrl}"
    "--state-dir=${stateDir}"
  ];
in
{
  imports = [
    ./ports.nix
    ./iap.nix
  ];

  options.bjackman.gerritCi = {
    enable = lib.mkEnableOption "the Gerrit CI runner";
    project = lib.mkOption {
      type = lib.types.str;
      default = "boxen";
      description = "The one project whose patch sets are checked.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.ci-bot-ssh-privkey = {
      file = ../secrets/ci-bot-ssh-privkey.age;
      owner = "gerrit-ci";
    };

    # Not root: it evaluates whatever anyone with push access uploads.
    users.users.gerrit-ci = {
      isSystemUser = true;
      group = "gerrit-ci";
      home = stateDir;
    };
    users.groups.gerrit-ci = { };

    bjackman.ports.gerrit-ci-logs = { };
    bjackman.iap.services.gerrit-ci-logs = {
      port = logPort;
      forwardAuth = true;
      allowedUsers = [ "brendan" ];
    };

    # Not http://127.0.0.1:port, which would also match only that Host, and the
    # proxy forwards the public one.
    services.caddy.virtualHosts."http://:${toString logPort}".extraConfig = ''
      bind 127.0.0.1
      root * ${stateDir}/logs
      file_server browse
    '';

    systemd.services.gerrit-ci = {
      after = [
        "gerrit.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      onFailure = [ "gerrit-ci-failed.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.bjackman.gerrit-ci}/bin/gerrit-ci ${flags}";
        User = "gerrit-ci";
        Group = "gerrit-ci";
        Restart = "always";
        RestartSec = 30;
        StateDirectory = "gerrit-ci";
        # Evaluation is the expensive phase and it grows with the flake, so
        # throttle before Gerrit's JVM feels it and die before the OOM killer
        # gets to choose. A unit that failed is an alert; a JVM that was picked
        # instead is a lost review queue.
        MemoryHigh = "3G";
        MemoryMax = "4G";
        # MemoryMax doesn't count swap, so without this the unit swaps its way
        # past it and fills the host's swap instead of dying.
        MemorySwapMax = "2G";
        # An evaluation killed for memory is a failed check, not a dead runner.
        OOMPolicy = "continue";
        # It can't use them - evaluation is the bottleneck and it's
        # single-threaded - and Jellyfin can.
        CPUQuota = "400%";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    # Reports that no result is coming. Separate from the runner because the
    # case worth reporting is the one where the runner was killed and can't
    # speak for itself.
    systemd.services.gerrit-ci-failed = {
      serviceConfig = {
        Type = "oneshot";
        User = "gerrit-ci";
        Group = "gerrit-ci";
      };
      path = [ pkgs.openssh ];
      script = ''
        change=$(cat ${stateDir}/in-flight 2>/dev/null || true)
        if [ -z "$change" ]; then
          echo "runner failed with nothing in flight; the unit failure is the report"
          exit 0
        fi
        ssh -i ${keyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
          -p ${toString config.bjackman.gerritSshPort} \
          ci-bot@${config.networking.hostName} \
          gerrit review "''${change/-/,}" \
          --message "'The CI runner died while checking this. When it restarts it will mark this patch set failed rather than retry it.'"
      '';
    };

    bjackman.impermanence.extraPersistence.directories = [
      {
        directory = stateDir;
        user = "gerrit-ci";
        group = "gerrit-ci";
        mode = "0755";
      }
    ];
  };
}
