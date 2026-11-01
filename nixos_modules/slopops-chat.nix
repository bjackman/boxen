# The slopops agent behind a chat page, packages/slopops/chat. Approving a tool
# call is a request to its socket, so only the reverse proxy may connect: not
# even the user the agent runs as.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bjackman.slopopsChat;
in
{
  options.bjackman.slopopsChat = {
    enable = lib.mkEnableOption "the slopops chat page";
    user = lib.mkOption {
      type = lib.types.str;
      description = "User the server and the agent run as. The agent's settings and instructions are its ~/.claude.";
    };
    allowedUser = lib.mkOption {
      type = lib.types.str;
      description = "The only Remote-User the server accepts.";
    };
    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/slopops-chat.sock";
    };
    socketGroup = lib.mkOption {
      type = lib.types.str;
      description = "Group of the reverse proxy, the only other user that may connect.";
    };
    workingDirPath = lib.mkOption {
      type = lib.types.str;
      description = "Where the agent works. It may be created by an ExecStartPre added to the service.";
    };
    stateDirPath = lib.mkOption {
      type = lib.types.str;
      description = "Where the conversation, session and push subscriptions are kept.";
    };
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    vapidSubject = lib.mkOption {
      type = lib.types.str;
      description = "Contact URL or mailto: that push services see.";
    };
    path = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages on the agent's PATH.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDirPath} 0700 ${cfg.user} ${config.users.users.${cfg.user}.group} -"
    ];

    systemd.sockets.slopops-chat = {
      wantedBy = [ "sockets.target" ];
      listenStreams = [ cfg.socketPath ];
      socketConfig = {
        SocketGroup = cfg.socketGroup;
        SocketMode = "0660";
      };
    };

    systemd.services.slopops-chat = {
      description = "slopops behind a chat page";
      requires = [ "slopops-chat.socket" ];
      after = [
        "slopops-chat.socket"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      inherit (cfg) path;
      environment = {
        SHELL = lib.getExe pkgs.bashInteractive;
        SLOPOPS_CHAT_STATE_DIR = cfg.stateDirPath;
        SLOPOPS_CHAT_CLAUDE_PATH = lib.getExe pkgs.llm-agents.claude-code;
        SLOPOPS_CHAT_MCP_CONFIG = pkgs.writers.writeJSON "slopops-mcp.json" cfg.mcpServers;
        SLOPOPS_CHAT_USER = cfg.allowedUser;
        SLOPOPS_CHAT_VAPID_SUBJECT = cfg.vapidSubject;
      };
      serviceConfig = import ./slopops-sandbox.nix // {
        User = cfg.user;
        Group = config.users.users.${cfg.user}.group;
        ExecStart = lib.getExe' pkgs.bjackman.slopops "slopops-chat";
        Restart = "always";
        RestartSec = "30s";
        WorkingDirectory = "-${cfg.workingDirPath}";

        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.stateDirPath ];
        ProtectHome = "tmpfs";
        # Claude Code keeps its sessions there, which resuming needs.
        BindPaths = [ config.users.users.${cfg.user}.home ];
        PrivateTmp = true;
      };
    };
  };
}
