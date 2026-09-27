{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./common.nix
  ];
  home = {
    username = "brendan";
    homeDirectory = "/home/brendan";
    packages = [
      # Claude Code only emits OSC 8 hyperlinks for terminals it recognises,
      # and it doesn't recognise foot.
      (pkgs.symlinkJoin {
        inherit (pkgs.llm-agents.claude-code) name meta;
        paths = [ pkgs.llm-agents.claude-code ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude --set FORCE_HYPERLINK 1
        '';
      })
    ];
  };
  programs.git.settings.user.email = "bhenryj0117@gmail.com";
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  programs.agent-skills.targets.claude.enable = true;
  home.file.".claude/settings.json".source =
    if config.bjackman.configCheckout == null then
      ../hm_files/common/claude/settings.json
    else
      config.lib.file.mkOutOfStoreSymlink "${config.bjackman.configCheckout}/hm_files/common/claude/settings.json";
}
