{ pkgs, pkgsUnstable, ... }:
{
  imports = [
    ./common.nix
    # Don't import this from common.nix because the secrets aren't exposed to
    # Google SSH keys.
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
}
