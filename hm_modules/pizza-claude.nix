{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  agent = osConfig.bjackman.homelab.users.slopbot;
in
{
  imports = [
    ./common.nix
    ./agent-host-context.nix
  ];

  bjackman.configCheckout = null;

  home.packages = [ pkgs.llm-agents.claude-code ];

  programs.git.settings.user = {
    name = agent.displayName;
    inherit (agent) email;
  };

  programs.agent-skills = {
    targets.claude.enable = true;
    skills.enable = [ "probe-homelab" ];
  };

  home.file.".claude/settings.json".source = (pkgs.formats.json { }).generate "claude-settings.json" (
    lib.importJSON ../hm_files/common/claude/settings.json
    // {
      skipDangerousModePermissionPrompt = true;
    }
  );

  bjackman.agentHostContext = ''
    # Operating on this host

    You're running on pizza, one of my homelab servers, as the unprivileged
    `claude` user. You were started by `claude remote-control`, which runs as a
    systemd service and spawns each session in its own git worktree of the
    `boxen` repository at ~/boxen. That repository holds the NixOS/Home Manager
    configs for this host and the rest of my machines.

    You have no sudo, and the service is sandboxed: everything outside your home
    directory (/var/lib/claude) is read-only. You can still use Nix normally,
    builds go through the host's nix-daemon. This is a fully flake-based system,
    so run tools you're missing with `nix run nixpkgs#<package>` or
    `nix shell nixpkgs#<package> -c <command>`.

    The host is small (8 cores, 7GB RAM) and runs real services, so avoid heavy
    parallel builds. If you hit a limit, ask me about it.

    ## Looking at the homelab

    Investigate the running homelab rather than guessing from the config.
    Prometheus answers PromQL over HTTP at `http://pizza:9090` with no auth,
    though it only keeps 15 days. For everything else there's `slop-probe`,
    which runs declared read-only commands on the homelab hosts, including this
    one. `slop-probe hosts` and then `slop-probe <host> list` are the
    authoritative answer to what you can run where. The `probe-homelab` skill
    has the recipes.

    If the probe you need doesn't exist, it goes in `nixos_modules/slop-probe.nix`
    in `boxen`: add it in your change, or tell me which probe you want. Don't go
    looking for another route in.

    ## Proposing changes

    Commit in your worktree, then run `slop-pr` from inside it: it pushes to
    Gerrit's `refs/for/master`, adds me as reviewer, and prints the change URL.
    Running it again uploads a new patch set. Amend the commit feedback is
    about rather than stacking fixups on top. You cannot push to master, and
    shouldn't try. Never deploy anything.

    Before telling me a change is ready, run `slop-review` in the worktree. It
    has the review bot review the topic's open changes, waits for it, and
    prints its findings with their comment ids. Deal with them as you would
    mine: amend, answer each with `slop-reply`, `slop-pr`, then `slop-review`
    again for the next round. The bot gives a change at most five rounds; if
    you still disagree after that, leave the thread unresolved for me.

    When I give you review comments to address, they come with their ids.
    Answer each where it was made with `slop-reply <change> <comment-id> <message>`, which threads the
    reply and resolves the thread. Pass `--unresolved` when you're disagreeing
    with me or the point still needs my attention.
  '';
}
