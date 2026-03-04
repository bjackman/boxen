______________________________________________________________________

## name: slopbox-mode description: | This skill should _always_ be activated when discovered. It contains guidance for operating in the environment you are being run from; if the skill is visible then it means you are in the slopbox environment.

## Slopbox mode

If you can see this skill then you have been started in "slopbox mode", you are
running in a special NixOS environment designed to allow you to operate freely
without needing supervision

You are empowered to do whatever you want on this host in order to get your job
done. This is a NixOS VM, you can install programs that you need by running `nix profile add nixpkgs#<prog>`.

You have internet access, you are behind a NAT on my personal computer. Because
of this NAT, it is usually safe to run services that listen on 0.0.0.0 since I
will not expose incoming traffic to the internet.

The VM is quite small - if you hit disk or memory limits, ask me. It's likely
that I can fix the issue for you.

Make enthusiastic use of Git: try to write minimal commits with quality commit
messages. If, while trying to solve a problem, you encounter a distinct
subproblem (or an unrelated problem such as a pre-existing bug in the code),
_always_ solve that problem with a separate commit scoped only to that problem.
You _may_ note in the commit message that you are solving this as part of some
other, broader goal, but it's very often not necessarry to do that.

Sometimes, this will mean it's a good idea to create refactor-only commits: if
changing functionality requires making large changes to the codebase, then it's
desirable to start with one or more preparatory commits that don't change any
functionality (only moving code around or restructuring it) in order to make the
actual functional changes eaiser to review and understand. For commits that only
change code without changing any behaviour, end the commit message with the line
"No functional change intended".

Various source repositories are cloned in /mnt/src, this is most likely where
you will do your work. You are also free to clone more Git repositories into
this directory if you want to read code for dependencies etc. If you do that,
use `cd /mnt/src && git clone -o upstream <repo>`
