{
  config,
  lib,
  pkgs,
  inputs,
  home-manager,
  pkgsUnstable,
  homelab,
  ...
}:
let
  homePath = "/var/lib/claude";
  checkoutPath = "${homePath}/boxen";
  slop = config.bjackman.slopClient.packages;
  gerrit = homelab.servers.gerrit;
  keyFilePath = config.age.secrets.slopbot-ssh-privkey.path;
  sshCommand = "ssh -i ${keyFilePath} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";

  prepare = pkgs.writeShellApplication {
    name = "claude-remote-control-prepare";
    runtimeInputs = with pkgs; [
      git
      jq
      openssh
    ];
    text = ''
      checkout_path=${checkoutPath}
      if [ ! -e "$checkout_path" ]; then
          GIT_SSH_COMMAND="${sshCommand}" git clone -c "core.sshCommand=${sshCommand}" \
              "ssh://slopbot@${gerrit.networking.hostName}:${toString gerrit.bjackman.gerritSshPort}/boxen" \
              "$checkout_path"
          scp -q -O -i ${keyFilePath} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
              -P ${toString gerrit.bjackman.gerritSshPort} \
              "slopbot@${gerrit.networking.hostName}:hooks/commit-msg" \
              "$checkout_path/.git/hooks/commit-msg"
          chmod +x "$checkout_path/.git/hooks/commit-msg"
      fi

      # Skip the first-run trust and Remote Control consent prompts, which would
      # otherwise read EOF from stdin and exit.
      config_path="$HOME/.claude.json"
      [ -e "$config_path" ] || (umask 077 && echo '{}' >"$config_path")
      tmp=$(mktemp "$config_path.XXXXXX")
      jq --arg dir "$checkout_path" \
          '.projects[$dir].hasTrustDialogAccepted = true | .remoteDialogSeen = true' \
          "$config_path" >"$tmp"
      mv "$tmp" "$config_path"
    '';
  };
in
{
  imports = [
    ../slop-client.nix
    home-manager.nixosModules.home-manager
  ];

  users.users.claude = {
    isSystemUser = true;
    group = "claude";
    home = homePath;
    createHome = true;
    shell = pkgs.bashInteractive;
  };
  users.groups.claude = { };

  bjackman.impermanence.extraPersistence.directories = [
    {
      directory = homePath;
      user = "claude";
      group = "claude";
      mode = "0700";
    }
  ];

  bjackman.slopClient.user = "claude";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users.claude.imports = [ ../../hm_modules/pizza-claude.nix ];
    extraSpecialArgs = inputs // {
      inherit pkgsUnstable homelab;
    };
  };

  systemd.services.claude-remote-control = {
    description = "Claude Code Remote Control server for boxen";
    after = [
      "network-online.target"
      "home-manager-claude.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Logging in is interactive: sudo -u claude -H /etc/profiles/per-user/claude/bin/claude auth login
    unitConfig.ConditionPathExists = "${homePath}/.claude/.credentials.json";
    # Claude Code refuses to run its Bash tool without a POSIX shell.
    environment.SHELL = lib.getExe pkgs.bashInteractive;
    path = [
      "/etc/profiles/per-user/claude"
      "/run/current-system/sw"
      pkgs.bashInteractive
      slop.slop-tools
      slop.slop-probe
    ];
    serviceConfig = {
      User = "claude";
      Group = "claude";
      WorkingDirectory = "-${checkoutPath}";
      ExecStartPre = lib.getExe prepare;
      ExecStart = lib.escapeShellArgs [
        "${pkgs.llm-agents.claude-code}/bin/claude"
        "remote-control"
        "--spawn"
        "worktree"
        "--permission-mode"
        "bypassPermissions"
        "--name"
        "pizza: boxen"
      ];
      Restart = "always";
      RestartSec = "30s";

      ProtectSystem = "strict";
      ReadWritePaths = [ homePath ];
      ProtectHome = true;
      PrivateTmp = true;
      MemoryMax = "3G";
      CPUQuota = "400%";
    };
  };
}
