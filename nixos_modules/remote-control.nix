# Claude Code Remote Control services: an agent I talk to from claude.ai/code,
# running in a checkout of boxen it fetches from Gerrit as slopbot.
{
  config,
  lib,
  pkgs,
  homelab,
  ...
}:
let
  gerrit = homelab.servers.gerrit;
  gerritPort = toString gerrit.bjackman.gerritSshPort;

  instanceModule =
    { name, config, ... }:
    {
      options = {
        description = lib.mkOption { type = lib.types.str; };
        user = lib.mkOption {
          type = lib.types.str;
          default = name;
        };
        createUser = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to create the account, rather than use one made elsewhere.";
        };
        homePath = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/${name}";
        };
        checkout = {
          path = lib.mkOption {
            type = lib.types.str;
            default = "${config.homePath}/boxen";
          };
          mirror = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Clone a bare mirror, for an agent that only reads the repository,
              rather than a checkout to make changes in.
            '';
          };
          keyFilePath = lib.mkOption {
            type = lib.types.str;
            description = "SSH key slopbot fetches from Gerrit with.";
          };
        };
        setup = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Shell run as the user before every start.";
        };
        claudeJson = lib.mkOption {
          type = with lib.types; attrsOf anything;
          default = { };
          description = "Top-level settings to set in ~/.claude.json.";
        };
        sessionName = lib.mkOption { type = lib.types.str; };
        permissionMode = lib.mkOption { type = lib.types.str; };
        extraArgs = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };
        path = lib.mkOption {
          type = with lib.types; listOf (either path str);
          default = [ ];
        };
        after = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };
        restartIfChanged = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        memoryMax = lib.mkOption { type = lib.types.str; };
        cpuQuota = lib.mkOption { type = lib.types.str; };
      };
    };

  prepare =
    name: instance:
    let
      sshArgs = [
        "-i"
        instance.checkout.keyFilePath
        "-o"
        "IdentitiesOnly=yes"
        "-o"
        "StrictHostKeyChecking=accept-new"
      ];
      sshCommand = lib.escapeShellArgs ([ "ssh" ] ++ sshArgs);
      checkoutPath = lib.escapeShellArg instance.checkout.path;
      cloneArgs = lib.escapeShellArgs (
        lib.optional instance.checkout.mirror "--mirror"
        ++ [
          "-c"
          "core.sshCommand=${sshCommand}"
          "ssh://slopbot@${gerrit.networking.hostName}:${gerritPort}/boxen"
          instance.checkout.path
        ]
      );
    in
    pkgs.writeShellApplication {
      name = "${name}-remote-control-prepare";
      runtimeInputs = with pkgs; [
        coreutils
        git
        jq
        openssh
      ];
      text = ''
        if [ ! -e ${checkoutPath} ]; then
            GIT_SSH_COMMAND=${lib.escapeShellArg sshCommand} git clone --quiet ${cloneArgs}
        ${
          lib.optionalString (!instance.checkout.mirror) ''
            scp -q -O ${lib.escapeShellArgs sshArgs} -P ${gerritPort} \
                "slopbot@${gerrit.networking.hostName}:hooks/commit-msg" ${checkoutPath}/.git/hooks/commit-msg
            chmod +x ${checkoutPath}/.git/hooks/commit-msg
          ''
        }fi
        ${instance.setup}
        # Skip the first-run trust and Remote Control consent prompts, which would
        # otherwise read EOF from stdin and exit.
        config_path="$HOME/.claude.json"
        [ -e "$config_path" ] || (umask 077 && echo '{}' >"$config_path")
        tmp=$(mktemp "$config_path.XXXXXX")
        jq --arg dir ${checkoutPath} --argjson extra ${lib.escapeShellArg (builtins.toJSON instance.claudeJson)} \
            '.projects[$dir].hasTrustDialogAccepted = true | .remoteDialogSeen = true | . + $extra' \
            "$config_path" >"$tmp"
        mv "$tmp" "$config_path"
      '';
    };

  instances = config.bjackman.remoteControl;
  forEach = f: lib.mkMerge (lib.mapAttrsToList f instances);
in
{
  options.bjackman.remoteControl = lib.mkOption {
    type = with lib.types; attrsOf (submodule instanceModule);
    default = { };
  };

  config = {
    users = forEach (
      _: instance: {
        users.${instance.user} = lib.mkMerge [
          {
            home = instance.homePath;
            createHome = true;
          }
          (lib.mkIf instance.createUser {
            isSystemUser = true;
            group = instance.user;
            shell = pkgs.bashInteractive;
          })
        ];
        groups = lib.mkIf instance.createUser { ${instance.user} = { }; };
      }
    );

    bjackman.impermanence.extraPersistence.directories = lib.mapAttrsToList (_: instance: {
      directory = instance.homePath;
      inherit (instance) user;
      group = instance.user;
      mode = "0700";
    }) instances;

    systemd.services = lib.mapAttrs' (
      name: instance:
      lib.nameValuePair "${name}-remote-control" {
        inherit (instance) description restartIfChanged;
        after = [ "network-online.target" ] ++ instance.after;
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "${instance.homePath}/.claude/.credentials.json";
        # Claude Code refuses to run its Bash tool without a POSIX shell.
        environment.SHELL = lib.getExe pkgs.bashInteractive;
        inherit (instance) path;
        serviceConfig = {
          User = instance.user;
          Group = instance.user;
          WorkingDirectory = "-${instance.checkout.path}";
          ExecStartPre = lib.getExe (prepare name instance);
          ExecStart = lib.escapeShellArgs (
            [
              "${pkgs.llm-agents.claude-code}/bin/claude"
              "remote-control"
            ]
            ++ instance.extraArgs
            ++ [
              "--permission-mode"
              instance.permissionMode
              "--name"
              instance.sessionName
            ]
          );
          Restart = "always";
          RestartSec = "30s";

          ProtectSystem = "strict";
          ReadWritePaths = [ instance.homePath ];
          ProtectHome = true;
          PrivateTmp = true;
          MemoryMax = instance.memoryMax;
          CPUQuota = instance.cpuQuota;
        };
      }
    ) instances;
  };
}
