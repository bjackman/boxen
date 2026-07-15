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
  ...
}:
let
  cfg = config.bjackman.agentHostContext;
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

  config = lib.mkIf (cfg != "") {
    home.file = lib.mapAttrs' (
      _: path: lib.nameValuePair path { source = contextFile; }
    ) enabledMemoryFiles;
  };
}
