{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.forgejo;
  repos = config.bjackman.forgejoGithubMirrors;
  # From https://api.github.com/meta.
  knownHosts = pkgs.writeText "github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  perRepo =
    f: lib.listToAttrs (map (repo: lib.nameValuePair "forgejo-github-mirror-${repo}" (f repo)) repos);
in
{
  options.bjackman.forgejoGithubMirrors = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
    description = ''
      Names of repos owned by `brendan` to mirror to the identically-named repo
      under github.com/bjackman.
    '';
  };

  config = lib.mkIf (repos != [ ]) {
    # The public half must be registered as a deploy key with write access on
    # each of the GitHub repos.
    age.secrets.github-mirror-privkey = {
      file = ../secrets/github-mirror-privkey.age;
      mode = "400";
      owner = cfg.user;
    };

    # Forgejo can push-mirror this itself, but that lives as per-repo rows in its
    # database and it reports failures only in its own UI. Since the mirror is the
    # only backup (see design_docs/forgejo.md), a sync that quietly stops working
    # is the thing to avoid: as a systemd unit, a broken mirror fails the unit and
    # trips the existing HostSystemdServiceCrashed alert.
    systemd.services = perRepo (repo: {
      description = "Mirror the ${repo} repo to GitHub";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.gitMinimal
        pkgs.openssh
      ];
      environment.GIT_SSH_COMMAND = lib.concatStringsSep " " [
        "ssh"
        "-i ${config.age.secrets.github-mirror-privkey.path}"
        "-o IdentitiesOnly=yes"
        "-o StrictHostKeyChecking=yes"
        "-o UserKnownHostsFile=${knownHosts}"
      ];
      script = ''
        git -C ${cfg.stateDir}/repositories/brendan/${repo}.git \
          push git@github.com:bjackman/${repo}.git \
          'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
      '';
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
      };
    });

    systemd.timers = perRepo (_: {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    });
  };
}
