# AGENTS.md

This is a kitchen-sink repository that I use to describe various Nix systems
that I use, mainly:

1. My PC and laptop

1. Home Manager configurations that I use on non-NixOS systems

1. Nodes in my homelab

## Slopbox mode

If you have been started in "slopbox mode", you are running in a special NixOS
environment designed to allow you to operate freely without needing supervision

- you are empowered to do whatever you want on this host in order to get your
  job done. This is a NixOS VM, you can install programs that you need by running
  `nix profile add nixpkgs#<prog>`.

You have internet access, you are behind a NAT on my personal computer. Because
of this NAT, it is usually safe to run services that listen on 0.0.0.0 since I
will not expose incoming traffic to the internet.

The VM is quite small - if you hit disk or memory limits, ask me. It's likely
that I can fix the issue for you.

## Using Git

### Normal mode

If _not_ in slopbox mode, do not modify the Git repository unless prompted, I
will usually prefer to do the Git operations myself.

Also, you are unlikely to be permitted to make nontrivial changes to the system

- if there are tools you need that aren't already provided in your environment
  or in this repository (via a package or a devShell), you'l need to ask the human
  user for assistance.

### Slopbox mode

If you've been prompted that you're in slopbox mode, read the rest of this
section to understand what that means - then, ask the user for the task you
should work on.

In slopbox mode, you should make enthusiastic use of Git: try to write minimal
commits with quality commit messages. If, while trying to solve a problem, you
encounter a distinct subproblem (or an unrelated problem such as a pre-existing
bug in the code), _always_ solve that problem with a separate commit scoped only
to that problem. You _may_ note in the commit message that you are solving this
as part of some other, broader goal, but it's very often not necessarry to do
that.

Sometimes, this will mean it's a good idea to create refactor-only commits: if
changing functionality requires making large changes to the codebase, then it's
desirable to start with one or more preparatory commits that don't change any
functionality (only moving code around or restructuring it) in order to make the
actual functional changes eaiser to review and understand. For commits that only
change code without changing any behaviour, end the commit message with the line
"No functional change intended".

Before commiting, always run `nix fmt`. Once you are done, let me know and I
will pull your commits into my main repo outside of your VM.

Commit titles look like "area: Brief summary of change". The "area" refers to
the part of the codebase that is being modified; this does _not_ follow the
"conventional commits" style. "Areas" are often nested with a slash, like
"nixos/pizza". The biggest "areas" are `nixos` usually meaning the code under
`nixos_modules/` or the related code in `flake.nix`, and `hm` (stands for Home
Manager), similar but for `hm_modules/`.
