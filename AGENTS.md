# AGENTS.md

This is a kitchen-sink repository that I use to describe various Nix systems
that I use, mainly:

1. My PC and laptop

1. Home Manager configurations that I use on non-NixOS systems

1. Nodes in my homelab

## Rules

These rules apply to your autonomous behaviour, if I ask you in-session to break
them then that's totally fine.

- You are probably connected to the Tailscale network that the hosts configured
  in here are on. You can feel free to run commands on them via SSH if they are
  "read-only" commands for gathering information.

- Persistent changes to the hosts should be made using code modifications
  wherever possible. Do not deploy these changes yourself unless prompted - just
  let me know when you've confirmed they compile etc, and I will usually deploy
  them myself.

- If you need to make non-config-as-code changes to the hosts, ask me about
  them. If you need to do this for experimental purposes, that's usually fine,
  just check in with me first and ensure we have an easy way to revert to a
  clean state afterwards.

### Version control - on my workstation

If you are running on one of my workstations (this is the default - if you're in
a special environment you'll be told explicitly), don't make any chances to the
git repository unless asked to, usually I'll want to do that myself. Exception:
it's fine to `git add` files so that Nix can see them.

If you have a reason to want to break this rule, it's OK to create a branch and
then make commitson that in a separate worktree.

### Version control - elsewhere

If I've run you in a special enviroment where you have full ownership of the git
repo, commit liberally:

- Try to keep commits as small and atomic as possible. If you're ever in doubt
  about commit boundaries, err on the side of more and smaller commits.

- Follow the commit title style the repo uses. Titles are usually like
  `<area>/<topic>: Blah`. The "topic" is can be excluded for stuff that just
  affects a whole area (probably refactorings). If it's included it very often
  corresponds to the name of a nix module. Some common areas:

- `flake`: Stuff to do with the overall organisation of the flake.

- `hm`: Home Manager modules.

- `nixos`: NixOS modules, for stuff relating to the "host setup".

- `tf`: Stuff relating to Terraform configuration.

- `homelab`: Stuff relating to homelab services. The distinction between this
  and `nixos`/`tf` is often fuzzy, just go on vibes.

Before pushing a PR or anything, always fetch and rebase onto master. If there
are nontrivial conflicts that require design decisions then stop and ask me
about those decisions, otherwise resolve them autonomously.

### Comments

Pay attention to these rules, I've had a hard time with this aspect of Claude's
behaviour and it's quite a pain point.

If you aren't certain whether a comment would break any of these rules, err on
the side of not commenting. It's always better to ask me if I'd like a comment
added rather than add one I don't like that has to be removed. I am quite
tolerant of large uncommented blocks of code but quite annoyed by unwanted
commentary.

- Keep comments concise.

- NEVER write comments about the change you're making ("this is now an integer",
  "fixed the bug here" etc). NEVER describe old behaviour that you have changed
  ("this used to silently hardcode x86"). NEVER refer to the conversation or
  user request that prompted the change. If you write comments, they should only
  ever describe the current state of the code.

- Assume the reader is fluent in Nix/NixOS/Home Manager/systemd/Linux. Never
  label what the code plainly says ("Foo's user-global settings" above a
  `home.file.".foo/settings.json"`), and never explain standard behaviour of the
  tools in use (store paths are read-only, what `mkIf` does, how a systemd timer
  fires). Comment _why_ - or when the code is doing something unusual enough that
  _what_ isn't obvious. Otherwise write no comment: that is the common case.

- In particular, don't justify a setting by restating its documented semantics,
  including its edge cases and defaults ("`ConditionACPower` also passes on
  machines with no mains supply"). Picking the option that does the obvious
  right thing is not noteworthy. If the comment would be redundant once the
  reader has the man page open, drop it; if the setting is genuinely subtle,
  a reference to the docs beats a paraphrase of them.

## Tips

- I use Fish and most hosts have Fish set up as the login shell for my user, but
  your Bash tool really does run Bash - write Bash syntax, and don't expect
  Fish's `$status` and friends to work.

- I tend not to install stuff globally, you'll find pretty standard stuff like
  `python` and `jq` absent from the `$PATH` (classic Unix coreutils like `awk`
  should always be there though). You can run these using `nix run` or `nix shell`
  instead.
