{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bjackman.nixCache;
  port = config.bjackman.ports.nix-cache.port;
  rootsDirPath = "/nix/var/nix/gcroots/nix-cache";
  keepRevisions = 3;

  warm = pkgs.writeShellApplication {
    name = "nix-cache-warm";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gitMinimal
      pkgs.jq
      config.nix.package
    ];
    text = ''
      rev=$(git ls-remote https://github.com/bjackman/boxen refs/heads/master | cut -f1)
      [ -n "$rev" ] || { echo "master not found" >&2; exit 1; }
      flake=github:bjackman/boxen/$rev
      hosts=$(nix eval --json "$flake#nixosConfigurations" --apply builtins.attrNames | jq -r '.[]')
      rev_dir=${rootsDirPath}/$rev
      mkdir -p "$rev_dir"
      touch "$rev_dir"

      status=0
      for host in $hosts; do
          [ -e "$rev_dir/$host" ] && continue
          echo "Building $host at $rev"
          nix build --out-link "$rev_dir/$host" \
              "$flake#nixosConfigurations.$host.config.system.build.toplevel" || status=1
      done

      kept=0
      while read -r dir; do
          complete=1
          for host in $hosts; do
              [ -e "$dir/$host" ] || complete=0
          done
          if [ "$complete" -eq 1 ] && [ "$kept" -lt ${toString keepRevisions} ]; then
              kept=$((kept + 1))
          elif [ "$dir" != "$rev_dir" ]; then
              rm -rf "$dir"
          fi
      done < <(find ${rootsDirPath} -mindepth 1 -maxdepth 1 -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2)
      exit "$status"
    '';
  };
in
{
  imports = [
    ./ports.nix
  ];

  options.bjackman.nixCache.serve = lib.mkEnableOption "serving this host's Nix store as a binary cache";

  config = lib.mkIf cfg.serve {
    bjackman.ports.nix-cache = { };

    age.secrets.nix-cache-signing-key.file = ../secrets/nix-cache-signing-key.age;

    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [ config.age.secrets.nix-cache-signing-key.path ];
      settings = {
        bind = "[::]:${toString port}";
        # Ahead of cache.nixos.org's 40.
        priority = 30;
      };
    };

    users.users.nix-cache = {
      isSystemUser = true;
      group = "nix-cache";
    };
    users.groups.nix-cache = { };

    systemd.tmpfiles.settings."10-nix-cache".${rootsDirPath}.d = {
      user = "nix-cache";
      group = "nix-cache";
      mode = "0755";
    };

    # Where norte's kernel and firmware are cached.
    nix.settings = {
      extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
      extra-trusted-public-keys = [
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    };

    systemd.services.nix-cache-warm = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        HOME = "/var/cache/nix-cache-warm";
        XDG_CACHE_HOME = "/var/cache/nix-cache-warm";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe warm;
        User = "nix-cache";
        Group = "nix-cache";
        CacheDirectory = "nix-cache-warm";
        # Each host is evaluated in a process of its own, and this can run
        # alongside gerrit-ci.
        MemoryHigh = "1500M";
        MemoryMax = "2G";
        MemorySwapMax = "1G";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };
    systemd.timers.nix-cache-warm = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnCalendar = "hourly";
        RandomizedDelaySec = "5m";
      };
    };

    # What's worth keeping is rooted above; this clears what gerrit-ci leaves.
    nix.gc = {
      automatic = true;
      dates = "weekly";
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
  };
}
