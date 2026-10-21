# Read-only, unauthenticated git:// access to some of Gerrit's repositories,
# for hosts on the tailnet that need to fetch them without a Gerrit account.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.bjackman.gerritGitDaemon;
  # DynamicUser puts the state here, and the repositories under basePath.
  repoDirPath = "/var/lib/private/gerrit/git";
  port = config.bjackman.ports.gerrit-git-daemon.port;
in
{
  imports = [ ./ports.nix ];

  options.bjackman.gerritGitDaemon = {
    repos = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Names of the Gerrit repositories to serve.";
    };
    url = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "git://${config.networking.hostName}:${toString port}";
      description = "Base URL of the repositories, without a trailing slash.";
    };
  };

  config = lib.mkIf (cfg.repos != [ ]) {
    bjackman.ports.gerrit-git-daemon.fixedPort = 9418;

    systemd.services.gerrit-git-daemon = {
      description = "Serve Gerrit repositories over git://";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = lib.escapeShellArgs (
          [
            "${pkgs.gitMinimal}/bin/git"
            "daemon"
            "--reuseaddr"
            "--strict-paths"
            "--export-all"
            "--base-path=${repoDirPath}"
            "--port=${toString port}"
          ]
          ++ map (repo: "${repoDirPath}/${repo}.git") cfg.repos
        );
        # As in github-mirror.nix: Gerrit's dynamic user, so that it can read
        # the repositories.
        DynamicUser = true;
        User = "gerrit";
        StateDirectory = "gerrit";
        Restart = "on-failure";
      };
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
  };
}
