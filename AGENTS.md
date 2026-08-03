# AGENTS.md

This is a kitchen-sink repository that I use to describe various Nix systems
that I use, mainly:

1. My PC and laptop

1. Home Manager configurations that I use on non-NixOS systems

1. Nodes in my homelab

Rules:

- Don't do anything to the Git repository unless asked, I usually prefer to
  commit changes myself.\`

- You are probably connected to the Tailscale network that the hosts configured
  in here are on. You can feel free to run commands on them via SSH if they are
  "read-only" commands for gathering information.

- Persistent changes to the hosts should be made using code modifications
  wherever possible. Do not deploy these changes yourself unless prompted - just
  let me know when you've confirmed they compile etc, and I will usually deply
  them myself.

- If you need to make non-config-as-code changes to the hosts, ask me about
  them. If you need to do this for experimental purposes, that's usually fine,
  just check in with me first and ensure we have an easy way to revert to a
  clean state afterwards.

- Keep comments concise. NEVER write comments about the change you're making
  ("this is now an integer", "fixed the bug here" etc), always comment on the
  code as it currently exists.

- Assume the reader is fluent in Nix/NixOS/Home Manager/systemd. Never label
  what the code plainly says ("Foo's user-global settings" above a
  `home.file.".foo/settings.json"`), and never explain standard behaviour of the
  tools in use (store paths are read-only, what `mkIf` does, how a systemd timer
  fires). Comment _why_ - or when the code is doing something unusual enough
  that _what_ isn't obvious. Otherwise write no comment: that is the common
  case.

Tips:

- I use Fish and most hosts have Fish set up as the login shell for my user. If
  you're running commands you might want to explicitly prefix them with `bash -c`,
  or just use Fish syntax.

- I tend not to install stuff globally, you'll find pretty standard stuff like
  `python` and `jq` absent from the `$PATH` (classic Unix coreutils like `awk`
  should always be there though). You can run these using `nix run` or `nix shell`
  instead.
