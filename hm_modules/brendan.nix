{
  config,
  pkgs,
  pkgsUnstable,
  ...
}:
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
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.bjackman.configCheckout}/hm_files/common/claude/settings.json";
}
