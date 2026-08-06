{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
    ./chungito-ctrl.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = with pkgs; [
      llm-agents.antigravity-cli
      llm-agents.claude-code
      vlc
      nautilus
    ];
  };
  programs.git.settings.user.email = "bhenryj0117@gmail.com";
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  programs.agent-skills.targets.claude.enable = true;
  home.file.".claude/settings.json".source = (pkgs.formats.json { }).generate "claude-settings.json" {
    model = "opus";
    effortLevel = "medium";
    agentPushNotifEnabled = true;
    tui = "fullscreen";
    respondToBashCommands = false;
  };
}
