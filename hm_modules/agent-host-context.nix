# Always-on "how to operate on this host" guidance for coding agents.
#
# The `agent-skills` library only manages Skills (lazily loaded by description),
# so it can't deliver guaranteed always-on context. This module fills that gap:
# it writes the guidance to each agent's always-loaded memory file (e.g.
# ~/.claude/CLAUDE.md).
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  cfg = config.bjackman.agentHostContext;

  # Off NixOS the login shell is set out-of-band (chsh), so there's nothing to
  # inspect; assume fish is the login shell if we bothered to configure it.
  loginShellIsFish =
    if osConfig == null then
      config.programs.fish.enable
    else
      (osConfig.users.users.${config.home.username}.shell.pname or "") == "fish";
  contextFile = pkgs.writeText "agent-host-context.md" cfg;

  contextFiles = {
    # Claude does not read ~/.config/agents/ at all.
    claude = ".claude/CLAUDE.md";
  };

  targets = config.programs.agent-skills.targets;
  enabledMemoryFiles = lib.filterAttrs (name: _: targets.${name}.enable or false) contextFiles;
in
{
  options.bjackman.agentHostContext = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = ''
      Markdown guidance telling coding agents how to operate on this host.
      Concatenated across modules ({option}`types.lines`), so a shared module
      can set a baseline and per-host modules can append specifics.

      Written to the always-on memory file of every {option}`programs.agent-skills`
      target that is both enabled and known to {file}`agent-host-context.nix`.
      Empty (the default) disables the feature.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf loginShellIsFish {
      bjackman.agentHostContext = lib.mkAfter ''
        My default shell is Fish, you can just use Fish syntax if you like or for
        nontrival commands you can just explicitly run them via `bash -c`.
      '';
    })
    (lib.mkIf (cfg != "") {
      home.file = lib.mapAttrs' (
        _: path: lib.nameValuePair path { source = contextFile; }
      ) enabledMemoryFiles;
    })
  ];
}
