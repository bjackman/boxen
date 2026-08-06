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
  '';
}
