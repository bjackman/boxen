# A read-only channel from the agent VM into this host. The agent reaches it
# over SSH, as an unprivileged user whose authorized_keys entry forces a command
# that can only run the probes declared here - so investigating prod needs no
# permission prompt and still can't change anything. Growing the set below is a
# pull request. See design_docs/agent_prod_access.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bjackman.slopProbe;

  paramModule = {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      flag = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Flag the value is passed as. Empty makes the parameter positional,
          ordered against the other positionals by `position`.
        '';
      };
      position = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
      regexpPattern = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          RE2 pattern the whole value must match. Empty makes the parameter a
          switch, which takes no value.

          This is the security boundary: a value that matches reaches the
          command as a single argv element, without a shell anywhere, so the
          pattern decides what the agent can ask for.
        '';
      };
      required = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  };

  probeModule = {
    options = {
      description = lib.mkOption { type = lib.types.str; };
      command = lib.mkOption {
        type = lib.types.path;
        description = "Executable to run. Nothing resolves it through PATH.";
      };
      args = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "Arguments always passed, before any the caller supplies.";
      };
      params = lib.mkOption {
        type = with lib.types; attrsOf (submodule paramModule);
        default = { };
      };
      maxBytes = lib.mkOption {
        type = lib.types.int;
        default = cfg.maxBytes;
      };
      timeout = lib.mkOption {
        type = lib.types.int;
        default = cfg.timeout;
      };
    };
  };

  manifest = pkgs.writers.writeJSON "slop-probe-manifest.json" {
    host = config.networking.hostName;
    probes = lib.mapAttrs (_: probe: {
      inherit (probe) description command args;
      maxBytes = probe.maxBytes;
      timeoutSeconds = probe.timeout;
      options = lib.mapAttrs (_: param: {
        inherit (param)
          description
          flag
          position
          regexpPattern
          required
          ;
      }) probe.params;
    }) cfg.probes;
  };

  server = "${pkgs.bjackman.slop-probe}/bin/slop-probe-server --manifest ${manifest}";

  systemctl = "${config.systemd.package}/bin/systemctl";
  unitParam = {
    description = "Unit name";
    regexpPattern = "[A-Za-z0-9@:_.-]+";
  };
in
{
  options.bjackman.slopProbe = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "slopbot";
      description = "Unprivileged account the agent's SSH sessions land in.";
    };

    authorizedKey = lib.mkOption {
      type = lib.types.str;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbMoDtPhYzvz0G2tu1qi/HjR3nK5qG4389VCrKh3pHH slopbot@probe";
      description = ''
        SSH public key the agent VM connects with. It goes into the probe
        user's authorized_keys behind a forced command, so holding it grants
        nothing beyond the probes declared here.
      '';
    };

    maxBytes = lib.mkOption {
      type = lib.types.int;
      default = 1024 * 1024;
      description = ''
        Default cap on a probe's output. This exists as much to protect the
        agent's context window as the host: an answer that doesn't fit should
        be a prompt to narrow the query.
      '';
    };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Default limit on how long a probe may run, in seconds.";
    };

    probes = lib.mkOption {
      type = with lib.types; attrsOf (submodule probeModule);
      default = { };
    };
  };

  config = {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      description = "Read-only homelab access for agents on slopbox";
      home = "/var/empty";
      # sshd runs the forced command through the account's shell.
      shell = pkgs.bash;
      extraGroups = [ "systemd-journal" ];
      openssh.authorizedKeys.keys = [
        ''restrict,command="${server}" ${cfg.authorizedKey}''
      ];
    };
    users.groups.${cfg.user} = { };

    bjackman.slopProbe.probes = {
      journal = {
        description = "Read the systemd journal";
        command = "${config.systemd.package}/bin/journalctl";
        # A caller-supplied --lines wins, being later on the command line.
        args = [
          "--no-pager"
          "--lines=1000"
        ];
        params = {
          unit = unitParam // {
            flag = "--unit";
          };
          identifier = {
            description = "Syslog identifier, for things that aren't a unit";
            flag = "--identifier";
            regexpPattern = "[A-Za-z0-9_.-]+";
          };
          since = {
            description = "Start of the window, e.g. -1h or '2026-08-19 12:00'";
            flag = "--since";
            regexpPattern = "[-+A-Za-z0-9 :,.]+";
          };
          until = {
            description = "End of the window";
            flag = "--until";
            regexpPattern = "[-+A-Za-z0-9 :,.]+";
          };
          priority = {
            description = "Maximum syslog priority, or a range like 0..3";
            flag = "--priority";
            regexpPattern = "[0-7]([.][.][0-7])?";
          };
          grep = {
            description = "Keep only messages matching this pattern";
            flag = "--grep";
            regexpPattern = ".{1,200}";
          };
          lines = {
            description = "How many entries to show";
            flag = "--lines";
            regexpPattern = "[0-9]{1,6}";
          };
          boot = {
            description = "Boot to read, e.g. -1 for the previous one";
            flag = "--boot";
            regexpPattern = "[-+]?[0-9]{1,3}|[0-9a-f]{32}";
          };
          output = {
            description = "Output format";
            flag = "--output";
            regexpPattern = "short|short-iso|short-precise|cat|json|verbose";
          };
          reverse = {
            description = "Newest first";
            flag = "--reverse";
          };
          dmesg = {
            description = "Kernel messages only";
            flag = "--dmesg";
          };
        };
      };

      unit-status = {
        description = "Show a unit's state, recent log lines and process tree";
        command = systemctl;
        args = [
          "status"
          "--no-pager"
          "--full"
        ];
        params.unit = unitParam // {
          position = 1;
          required = true;
        };
      };

      unit-show = {
        description = "Dump a unit's resolved properties";
        command = systemctl;
        args = [
          "show"
          "--no-pager"
        ];
        params = {
          unit = unitParam // {
            position = 1;
            required = true;
          };
          property = {
            description = "Comma-separated properties, rather than all of them";
            flag = "--property";
            regexpPattern = "[A-Za-z]+(,[A-Za-z]+)*";
          };
        };
      };

      units = {
        description = "List units and their state";
        command = systemctl;
        args = [
          "list-units"
          "--no-pager"
          "--all"
        ];
        params = {
          glob = {
            description = "Glob to match unit names against";
            position = 1;
            regexpPattern = "[A-Za-z0-9@:_.*?-]+";
          };
          failed = {
            description = "Only units in a failed state";
            flag = "--failed";
          };
          type = {
            description = "Unit type, e.g. service or timer";
            flag = "--type";
            regexpPattern = "[a-z]+";
          };
        };
      };

      timers = {
        description = "List timers with their last and next elapse";
        command = systemctl;
        args = [
          "list-timers"
          "--no-pager"
          "--all"
        ];
      };

      processes = {
        description = "Snapshot of running processes, heaviest first";
        command = "${pkgs.procps}/bin/ps";
        args = [
          "-eo"
          "pid,ppid,user,pcpu,pmem,etime,args"
          "--sort=-pcpu"
        ];
      };

      disk-free = {
        description = "Filesystem usage";
        command = "${pkgs.coreutils}/bin/df";
        args = [
          "-h"
          "--local"
        ];
      };

      generations = {
        description = "System generations, to line an incident up against a deploy";
        command = "${pkgs.coreutils}/bin/ls";
        args = [
          "-l"
          "--time-style=long-iso"
          "/nix/var/nix/profiles/"
        ];
      };

      current-system = {
        description = "Store path of the running system";
        command = "${pkgs.coreutils}/bin/readlink";
        args = [
          "-f"
          "/run/current-system"
        ];
      };

      closure-diff = {
        description = "What changed between two system closures";
        command = "${config.nix.package}/bin/nix";
        args = [
          "--extra-experimental-features"
          "nix-command"
          "store"
          "diff-closures"
        ];
        params =
          let
            storePath = {
              regexpPattern = "/nix/store/[a-z0-9]{32}-[A-Za-z0-9@._+-]+";
              required = true;
            };
          in
          {
            from = storePath // {
              description = "Closure to compare from";
              position = 1;
            };
            to = storePath // {
              description = "Closure to compare to";
              position = 2;
            };
          };
      };
    }
    // lib.optionalAttrs config.boot.zfs.enabled {
      zpool-status = {
        description = "ZFS pool health";
        command = "${config.boot.zfs.package}/bin/zpool";
        args = [ "status" ];
      };

      zfs-list = {
        description = "ZFS datasets with their space usage";
        command = "${config.boot.zfs.package}/bin/zfs";
        args = [
          "list"
          "-o"
          "name,used,avail,refer,mountpoint"
        ];
      };
    };
  };
}
