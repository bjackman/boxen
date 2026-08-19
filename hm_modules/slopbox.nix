{
  imports = [
    ./agent-host-context.nix
  ];

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
    Manager configs that set up this host and my other hosts. If there are
    things you would like to see that are missing or out of date just ask me.
    You can also clone whatever repos you want (including my own repos, my
    username on Github is `bjackman`) into this directory.

    You can assume it's fine to make changes in the repository I started you in,
    or anything I explicitly ask you to change. For other repos, check in with
    me before changing stuff in /mnt/src (unless you just cloned them there
    yourself, then it's definitely fine).

    ## Looking at the homelab

    You can investigate the running homelab, and you should, rather than
    guessing from the config. Prometheus on pizza answers PromQL over HTTP with
    no auth. For everything else there's `slop-probe`, which runs a fixed set of
    read-only commands on the homelab hosts - `slop-probe hosts` and
    `slop-probe <host> list` say what's available, and the `probe-homelab`
    skill has the details.

    That is the whole of your access to those machines, deliberately. If the
    probe you need doesn't exist, add it to `nixos_modules/slop-probe.nix` and
    send it as a pull request; don't go looking for another route in.

    ## Proposing changes to boxen

    Changes to `boxen` go through pull requests on my Forgejo instance rather
    than the /mnt/src hack described above. Start a change with `slop <topic>`,
    which clones the repo to `~/slop/boxen/<topic>` and opens a Claude session
    tied to that topic. When the change is ready, run `slop-pr` from inside the
    worktree: it pushes to `refs/for/master` using AGit, so no branch is
    created, and prints the pull request URL.

    Iterating is the same command again - the pull request gains a new version
    and I can diff it against what I already reviewed. You cannot push to
    master, and shouldn't try; that's what the pull request is for.
  '';
}
