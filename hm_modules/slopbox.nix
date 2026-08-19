{
  lib,
  pkgs,
  homelab,
  ...
}:
let
  # Everything committed on this host is the agent's work, and Gerrit rejects a
  # push whose committer isn't a registered address of the pushing account.
  agent = homelab.servers.gerrit.bjackman.homelab.users.slopbot;
in
{
  imports = [
    ./agent-host-context.nix
  ];

  programs.git.settings.user = {
    name = agent.displayName;
    email = lib.mkForce agent.email;
  };

  # The worktrees under ~/slop are the only checkouts here; there's no
  # long-lived one for config to link into.
  bjackman.configCheckout = null;

  # slop(1) starts every session in bypassPermissions mode, which is the whole
  # point of this host, so the disclaimer has nothing to warn me about.
  home.file.".claude/settings.json".source = lib.mkForce (
    (pkgs.formats.json { }).generate "claude-settings.json" (
      lib.importJSON ../hm_files/common/claude/settings.json
      // {
        skipDangerousModePermissionPrompt = true;
      }
    )
  );

  # The homelab probe recipes are useful in any session on this host, not just
  # ones started in a boxen checkout, so they ship as a user skill rather than
  # living in the repo's .agents/skills.
  programs.agent-skills.skills.enable = [ "probe-homelab" ];

  bjackman.agentHostContext = ''
    # Operating on this host

    This is slopbox a VM running on my desktop, Chungito, created specifically
    to allow you to operate without harness constraints - you ought to be
    allowed to do anything you want on this host. You have internet access, from
    behind a NAT. Because of this NAT it's usually safe to run services that
    listen on 0.0.0.0, I will not expose it to the internet.

    The VM is quite small, if you hit disk or memory limits, ask me about it,
    it's quite likely that this is not a fundamental limitation, and I'm easily
    able to resolve it for you.

    This is set up as an Incus VM, with a virtiofs directory mounted in
    /mnt/src. This directory contains clones of local source trees, from another
    directory on the host. That directory doesn't exist in the guest so you'll
    see a git remote that doesn't actually work. The idea is that you can just
    commit with no permissions or approvals and then I'll manually pull your
    changes into the main repo on the host. Unfortunately I've run into some
    issues with Nix with this funny repo hack, apparently due to interactions
    between libgit2 and virtiofs. If you get errors like `error: getting Git
    object 'c59baa078c847281097ac45059945deb6ceb7e28': object not found - no
    match for id (c59baa078c847281097ac45059945deb6ceb7e28) (libgit2 error code
    = 9)`. You can work around this by forcing nix to use a `path`-based
    flakeref, e.g. `nix build path:.`.

    Various source repositories are cloned in /mnt/src, feel free to look into
    them. The likely interesting one is `boxen` which contains the NixOS/Home
    Manager configs that set up this host and my other hosts. These clones are
    snapshots and go stale - I refresh them by hand - so for `boxen` in
    particular, read /mnt/src/boxen only to get your bearings: if you're in a
    boxen worktree already, trust that instead, and if you aren't, treat the
    snapshot as reference and check with me before changing anything. If there
    are things you would like to see that are missing or out of date just ask
    me.
    You can also clone whatever repos you want (including my own repos, my
    username on Github is `bjackman`) into this directory.

    You can assume it's fine to make changes in the repository I started you in,
    or anything I explicitly ask you to change. For other repos, check in with
    me before changing stuff in /mnt/src (unless you just cloned them there
    yourself, then it's definitely fine).

    ## Looking at the homelab

    You can investigate the running homelab, and you should, rather than
    guessing from the config. Prometheus on pizza answers PromQL over HTTP at
    `http://pizza:9090` with no auth, though it only keeps 15 days. For
    everything else there's `slop-probe`, which runs declared read-only commands
    on the homelab hosts. Each host declares its own set, so `slop-probe hosts`
    and then `slop-probe <host> list` are the authoritative answer to what you
    can run where. The `probe-homelab` skill has the recipes.

    You have no shell on those machines and no key for one, so `slop-probe` is
    in practice all the access you have, and that's deliberate. If the probe you
    need doesn't exist, it goes in `nixos_modules/slop-probe.nix` in the `boxen`
    repo: add it there and send a pull request if you're in a worktree, and
    otherwise just tell me which probe you want. Don't go looking for another
    route in.

    ## Proposing changes to boxen

    Changes to `boxen` go through Gerrit rather than the /mnt/src hack described
    above. I start a change with `slop <topic>`, which clones the repo to
    `~/slop/boxen/<topic>` and opens a Claude session there - that's likely how
    you got here. `slop` is my way of starting you, not your way of getting a
    checkout: running it yourself would just open a second session inside this
    one. When the change is ready, run `slop-pr` from inside the worktree: it
    pushes to `refs/for/master`, so no branch is created, and prints the change
    URL.

    Iterating is the same command again, and it produces a new patch set that I
    can diff against the one I already reviewed. Amend the commit the feedback
    is about rather than stacking a fixup on top: each commit is a separate
    change under review, and a series is held together by its topic. You cannot
    push to master, and shouldn't try.

    When I leave review comments you'll be asked to address them, with each
    comment's id in brackets. Answer them where they were made, with
    `slop-reply <change> <comment-id> <message>`, which threads the reply under
    my comment and marks that thread resolved. Pass `--unresolved` instead when
    you're disagreeing with me or the point still needs my attention - a thread
    resolved because you complied and one left open because you didn't are both
    useful to me, and silently doing neither isn't.
  '';
}
