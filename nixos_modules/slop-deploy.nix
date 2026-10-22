# Lets an agent deploy this host, but only to a commit of the branch that is its
# tip or recent. The agent reaches it like the probes, through a forced command
# behind an SSH key of its own, and the policy is checked here by the root unit
# that does the deploy, so nothing the agent runs elsewhere can widen it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bjackman.slopDeploy;
  hostName = config.networking.hostName;
  mirrorPath = "/var/lib/slop-deploy/repo.git";
  switchUnit = "slop-deploy-switch";

  run = pkgs.writeShellApplication {
    name = "slop-deploy-run";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.util-linux
      config.nix.package
      config.systemd.package
    ];
    text = ''
      rev=$1
      fail() {
          echo "$*" >&2
          exit 1
      }

      exec 9>/run/slop-deploy.lock
      flock --nonblock 9 || fail "Another deploy is running"

      [ -d ${mirrorPath} ] || git init --quiet --bare ${mirrorPath}
      git -C ${mirrorPath} fetch --quiet --force ${lib.escapeShellArg cfg.repoUrl} \
          "+refs/heads/${cfg.branch}:refs/heads/${cfg.branch}"
      tip=$(git -C ${mirrorPath} rev-parse "refs/heads/${cfg.branch}")

      { git -C ${mirrorPath} cat-file -e "$rev^{commit}" 2>/dev/null &&
          git -C ${mirrorPath} merge-base --is-ancestor "$rev" "$tip"; } ||
          fail "$rev is not on ${cfg.branch}"
      if [ "$rev" != "$tip" ]; then
          committed=$(git -C ${mirrorPath} show --no-patch --format=%ct "$rev")
          age_days=$((($(date +%s) - committed) / 86400))
          [ "$age_days" -lt ${toString cfg.maxAgeDays} ] ||
              fail "$rev is $age_days days old, only the tip of ${cfg.branch} or a commit from the last ${toString cfg.maxAgeDays} days can be deployed"
      fi

      echo "Building $rev"
      toplevel=$(${cfg.build} ${mirrorPath} "$rev")
      echo "Switching to $toplevel"
      nix-env --profile /nix/var/nix/profiles/system --set "$toplevel"
      # In a unit of its own, as nixos-rebuild does it, so that the switch
      # survives this unit being stopped by a system that doesn't have it.
      systemd-run -E LOCALE_ARCHIVE --collect --no-ask-password --pipe --quiet \
          --service-type=exec --unit=${switchUnit} \
          "$toplevel/bin/switch-to-configuration" switch
      echo "Deployed $rev"
    '';
  };

  # The one thing the deploy user may run as root. sudo passes it whatever
  # arguments it's given, so it checks the commit itself before making a unit
  # name of it.
  start = pkgs.writeShellApplication {
    name = "slop-deploy-start";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      if [[ $# -ne 1 || ! $1 =~ ^[0-9a-f]{40}$ ]]; then
          echo "Usage: slop-deploy-start <full commit hash>" >&2
          exit 1
      fi
      exec systemctl start "slop-deploy@$1.service"
    '';
  };

  request = pkgs.writeShellApplication {
    name = "slop-deploy-request";
    runtimeInputs = [
      pkgs.coreutils
      config.systemd.package
    ];
    text = ''
      since=$(date +%s)
      status=0
      ${config.security.wrapperDir}/sudo --non-interactive ${lib.getExe start} "$1" || status=$?
      # The switch logs as its own unit. Deploys are serialised, so the one in
      # this window is ours.
      journalctl --no-pager --output=cat --unit="slop-deploy@$1.service" --unit=${switchUnit} \
          --since="@$since"
      exit "$status"
    '';
  };

  manifest = pkgs.writers.writeJSON "slop-deploy-manifest.json" {
    host = hostName;
    probes.deploy = {
      description = ''
        Deploy a commit of ${cfg.branch}: its tip, or one committed in the last
        ${toString cfg.maxAgeDays} days. Waits for the deploy to finish and prints its log.
      '';
      command = lib.getExe request;
      args = [ ];
      maxBytes = 1024 * 1024;
      timeoutSeconds = cfg.timeout;
      options.rev = {
        description = "Full hash of the commit";
        flag = "";
        position = 1;
        regexpPattern = "[0-9a-f]{40}";
        required = true;
      };
    };
  };
in
{
  options.bjackman.slopDeploy = {
    enable = lib.mkEnableOption "deploys of this host by an agent";

    user = lib.mkOption {
      type = lib.types.str;
      default = "slopops";
      description = "Account the agent's deploy requests land in.";
    };

    authorizedKey = lib.mkOption {
      type = lib.types.str;
      description = ''
        SSH public key the agent deploys with. Keep it separate from the probe
        key: holding this one lets the holder change what the host runs.
      '';
    };

    repoUrl = lib.mkOption {
      type = lib.types.str;
      description = "Git repository whose branch decides what may be deployed.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "master";
    };

    maxAgeDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "How old a commit other than the tip may be, by commit date.";
    };

    build = lib.mkOption {
      type = lib.types.path;
      default = pkgs.writeShellScript "slop-deploy-build" ''
        exec ${config.nix.package}/bin/nix --extra-experimental-features "nix-command flakes" \
            build --no-link --print-out-paths \
            "git+file://$1?rev=$2#nixosConfigurations.${hostName}.config.system.build.toplevel"
      '';
      description = ''
        Executable that builds the system to deploy. It is given the path of a
        bare mirror of the repository and the commit, and prints the store path
        of the system's top level.
      '';
    };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 60 * 60;
      description = ''
        How long a deploy request waits, in seconds. The deploy itself carries
        on after this, it just stops being reported to the caller.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      description = "Lets agents deploy commits of ${cfg.branch}";
      # A host where the agent itself runs as this account gives it a real one.
      home = lib.mkDefault "/var/empty";
      shell = pkgs.bash;
      extraGroups = [ "systemd-journal" ];
      openssh.authorizedKeys.keys = [
        ''restrict,command="${pkgs.bjackman.slop-probe}/bin/slop-probe-server --manifest ${manifest}" ${cfg.authorizedKey}''
      ];
    };
    users.groups.${cfg.user} = { };

    systemd.services."slop-deploy@" = {
      description = "Deploy commit %i of ${cfg.branch}";
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe run} %i";
        SyslogIdentifier = "slop-deploy";
        StateDirectory = "slop-deploy";
      };
    };

    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        runAs = "root";
        commands = [
          {
            command = lib.getExe start;
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
