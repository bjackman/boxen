# slopops: an agent that deploys the homelab

**Status: proposed, and being built alongside this document.** Sibling to
[`agent_prod_access.md`](agent_prod_access.md), which lets agents look at the
homelab but not change it. This is the one change worth handing over:
deploying what review has already put on master.

## Goals

1. I can talk to an agent about the homelab's deploys from claude.ai/code or
   the phone app: what's running where, what master is ahead by, whether the
   last deploy is healthy. It can answer from the live hosts.
1. It can deploy, and roll back, for real. At first every deploy waits for me
   to approve it. A rollback is a deploy of an earlier commit of master, so it
   is limited the same way: if no commit from the last 30 days is good, the
   agent says so, and getting back is mine to do with deploy-rs.
1. Later it notices on its own that master has moved and offers to deploy,
   and later still it deploys the ordinary case without asking.

Non-goal, as in `agent_prod_access.md`: defending against a hostile agent. The
thing being contained is a confused agent deploying at a bad moment.

## Background

### What exists

- `nixos_modules/slop-deploy.nix`. A host that enables it accepts a deploy of
  the tip of master, or of a commit of master from the last 30 days, from the
  `slopops` account over SSH. The policy is checked on the host, by the root
  unit `slop-deploy@<commit>.service` that does the deploy. `tests/slop-deploy.nix`
  checks it in a VM. pizza, norte and sandy enable it.
- `slop-probe`, for observing the hosts, and Prometheus on pizza.
- `claude remote-control` on pizza, which is how I already talk to the coding
  agents (`nixos_modules/pizza/claude.nix`).

### A session can be woken by a Routine

`review_bot.md` found nothing that pushes a message into a running session,
and locally that's still true: the CLI has no command for it. But a Routine (a
schedule held by claude.ai) can be bound to a session, and its message arrives
as a new turn. Tested on 2026-10-18 from a remote-control session on pizza: a
message scheduled for 13:57:00 had arrived by 13:57:42. Routines normally fire
at most hourly. Firing one when something happens, rather than on a schedule,
needs a call from inside a session.

## Decisions

1. **slopops is a Remote Control session, not a chat loop of its own.**
   `slopops-remote-control` runs `claude remote-control` as `slopops` on pizza,
   with its own login, home and mirror of boxen. On pizza that's the account
   slop-deploy makes for deploys, which defaults its home to `/var/empty`;
   pizza overrides it with a real one. claude.ai/code already gives
   a UI on web and phone, notifications, resumable sessions and approval
   prompts. Building those around the Agent SDK would be most of the work, for
   no gain in what the agent can do.

1. **Deploying is an MCP tool behind an approval prompt.** `packages/slopops`
   is a small MCP server whose `deploy` tool runs a deploy and waits for it.
   Its permission rule is `ask`, so every deploy appears on my phone with the
   host and commit, and I approve or deny it. Observation is allowed without
   asking: `slop-probe`, `git` on the mirror, Prometheus, and read-only
   filters to pipe them through. Anything else asks too. Unlike the coding
   sessions it doesn't run with `bypassPermissions`.

1. **The approval prompt is about judgement; the host is the boundary.** The
   prompt is enforced by Claude Code, not by anything the agent can't touch.
   The deploy key is `/run/agenix/slopops-ssh-privkey`, readable by `slopops`,
   which is the account the agent runs as. What keeps it from being used
   without asking is only that every command able to use it asks first:

   - The allowed commands can't use it. The `slop-probe` rules are anchored on
     the host (`slop-probe pizza …`), because the client's own flags, given
     before the host, override its wrapper's and could point it at the deploy
     key. After the host they're probe options, which the host refuses. `git fetch` is allowed only bare, since `--upload-pack` runs a command.
   - The ways round the tool are denied rather than left to ask: `slop-deploy`
     from Bash, and `sudo`, since on pizza `slopops` is also the account
     slop-deploy lets start a deploy.
   - An `ask` rule holds even if the session is started with
     `--permission-mode bypassPermissions` (checked with Claude Code 2.1.300),
     so a stray flag on the service can't quietly turn the prompts off.

   That's acceptable because getting round it gains little: the host still
   only accepts a reviewed commit of master from the last month. If that stops
   being enough, the key moves to a separate user and the MCP server runs as
   that user behind a socket.

1. **What it can see of master is a mirror it fetches itself, from Gerrit.**
   It uses slopbot's Gerrit key, as the coding sessions' checkout does. The
   host decides against its own fetch, so the two can disagree for as long as
   it takes one of them to fetch; the agent fetches before it reasons about
   master.

1. **Its instructions say how to judge health.** The deploy's exit status
   isn't enough: a switch that leaves units failed has still switched. Failed
   units and errors in the journal since the deploy, compared with before it,
   decide whether to recommend a rollback.

1. **The service doesn't restart when its own configuration changes.** pizza
   deploys pizza, so a deploy that changes the service would otherwise restart
   the session that asked for it. The deploy itself survives that, being a
   unit, but the conversation shouldn't drop. The change takes effect when the
   service is next restarted on purpose.

1. **Other hosts fetch master from Gerrit over git://.** Only pizza can read
   Gerrit's repository from disk. `gerrit-git-daemon` serves `boxen` from it
   read-only, unauthenticated, and only to the tailnet, so norte and sandy
   check against what Gerrit has without credentials of their own. The GitHub
   mirror would have served too, but it lags by up to an hour, and whoever
   could push to it would decide what's deployable.

1. **Each host builds itself.** norte and sandy evaluate their own configs, as
   pizza does. Building elsewhere would mean trusting that host's word for
   which system a commit is. norte substitutes what nix-cache-warm has built;
   sandy, being away from home, uses cache.nixos.org and builds the rest.

1. **Evaluating a deploy doesn't get to starve Gerrit.** Building pizza on
   pizza starts with a 1.7G evaluation next to Gerrit's JVM, so the deploy
   unit has the same `MemoryHigh`/`MemoryMax`, niceness and I/O class as
   gerrit-ci. As for gerrit-ci, those bound only the evaluation: builds run in
   nix-daemon, outside the unit. A pizza closure is mostly substituted rather
   than built, so that's left alone until a deploy shows otherwise. norte and
   sandy cap the evaluation too, below what their own services leave free.

## Phases

1. **Interactive.** Every deploy needs approval. pizza first, then norte and
   sandy.
1. **Knowing what's running.** A probe for
   `/run/current-system/configuration-revision`, so that "pizza is three
   commits behind" doesn't need guessing from store paths.
1. **Proactive.** An hourly Routine bound to the session asks it to check
   whether master has moved; if it has, the agent proposes a deploy for me to
   approve.
1. **Earned autonomy.** Auto-approve the ordinary case (the tip passed CI, the
   host is healthy before and after) and keep the prompt for rollbacks and
   anything unusual.

## Open questions

1. **How long a Routine's binding lasts.** It names one session. Whether that
   survives the service restarting, or claude.ai archiving an idle session, is
   untested.
1. **The real build.** The VM test fakes it: each fixture commit names a system
   already in the VM's store. `nix build` of the flake at the commit first runs
   for real on pizza.
1. **Evaluating on a Pi.** Whether norte's and sandy's caps leave the
   evaluation enough, and how slow it is, is untested until the first deploy.
1. **Memory and history.** The hosts' journals are the record of what was
   deployed. Whether the agent's own notes between sessions are worth having
   is something to find out by using it.
