{
  pkgs,
  lib,
  config,
  ...
}:
let
  # DynamicUser puts the state here, and the repositories under basePath.
  repoDir = "/var/lib/private/gerrit/git";
  repos = config.bjackman.githubMirrors;
  # From https://api.github.com/meta.
  knownHosts = pkgs.writeText "github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  perRepo = f: lib.listToAttrs (map (repo: lib.nameValuePair "github-mirror-${repo}" (f repo)) repos);
in
{
  options.bjackman.githubMirrors = lib.mkOption {
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
    };

    # Gerrit's replication plugin would do this, but it reports failure into a
    # web UI I won't look at. Since the mirror is the only backup (see
    # design_docs/gerrit.md), a sync that quietly stops working is the thing to
    # avoid: as a systemd unit, a broken mirror fails the unit and trips the
    # existing HostSystemdServiceCrashed alert.
    systemd.services = perRepo (repo: {
      description = "Mirror the ${repo} repo to GitHub";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.gitMinimal
        pkgs.openssh
      ];
      script = ''
        # The key is a credential rather than a file read straight from
        # /run/agenix, because it has to be readable by a UID that doesn't exist
        # until the unit starts.
        export GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/github-key \
          -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
          -o UserKnownHostsFile=${knownHosts}"
        git -C ${repoDir}/${repo}.git \
          push git@github.com:bjackman/${repo}.git \
          'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
      '';
      serviceConfig = {
        Type = "oneshot";
        # systemd allocates dynamic users by name, so asking for Gerrit's lands
        # on the same UID and can read its repositories - no root, and no
        # overriding the module's choice of DynamicUser.
        DynamicUser = true;
        User = "gerrit";
        StateDirectory = "gerrit";
        LoadCredential = "github-key:${config.age.secrets.github-mirror-privkey.path}";
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
