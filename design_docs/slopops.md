# slopops: an agent that deploys the homelab

**Status: in use, at phase 1.** Sibling to
[`agent_prod_access.md`](agent_prod_access.md), which lets agents look at the
homelab but not change it. This is the one change worth handing over:
deploying what review has already put on master.

## Goals

1. I can talk to an agent about the homelab's deploys from my phone or a
   browser: what's running where, what master is ahead by, whether the
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
- `claude remote-control` on pizza, which is how I talk to the coding agents
  (`nixos_modules/pizza/claude.nix`).

## Decisions

1. **slopops is a chat page of its own.** `packages/slopops/chat` is a
   server on pizza that runs the agent through the Agent SDK, behind Caddy
   and Authelia like the other services, with the review bot's long-lived
   token. It keeps the conversation and its own approval prompts, and
   notifies with Web Push. It runs as `slopops`, the account slop-deploy
   makes for deploys, which defaults its home to `/var/empty`; pizza gives it
   a real one, with the mirror of boxen in it.

   **Rejected: a Remote Control session**, as the coding agents are.
   claude.ai/code would give it a UI on web and phone, notifications,
   resumable sessions and approval prompts for nothing, and slopops started
   out as one. But the session is tied to claude.ai. It needs an interactive
   login that expires, and the only way to start a turn from outside is a
   Routine bound to the session: a schedule held by claude.ai, firing at most
   hourly. The chat server owns the conversation, so it can start a turn
   itself.

1. **Deploying is an MCP tool behind an approval prompt; nothing else asks.**
   `packages/slopops` is a small MCP server whose `deploy` tool runs a deploy
   and waits for it. Its permission rule is `ask`, so every deploy appears on
   my phone with the host and commit, and I approve or deny it. Every other
   command is allowed outright.

   **Rejected: allowing only read-only commands.** The agent's commands
   rarely fit a list: nearly every one combined an allowed command with
   `echo`, a ref listing or a loop, so it asked about everything. And each
   entry needed checking for a way to run or write something: even
   `git branch -a -m` renames a branch.

1. **The approval prompt is about judgement; the host is the boundary.** The
   prompt is enforced by Claude Code and by the agent following its
   instructions, not by anything the agent can't touch. The deploy key is
   `/run/agenix/slopops-ssh-privkey`, readable by `slopops`, the account the
   agent runs as, and Bash can run anything. What keeps it to the tool is:

   - Its instructions, and its judgement: they say never to use the key,
     `ssh` or `slop-deploy` to get round asking.
   - A weak sandbox, in the chat service's unit
     (`nixos_modules/slopops-chat.nix`). It can't gain privileges, so `sudo`
     fails even on pizza, where `slopops` is also the account slop-deploy
     lets start a deploy. It has no capabilities, can't see other users'
     processes, and finds the system read-only apart from its home.
   - Denying `slop-deploy` and `sudo` from Bash, as guard rails against a
     mistake rather than a boundary.
   - Answering a prompt is a request to the chat server, which listens on a
     socket owned by root and Caddy's group. `slopops` can't open it, so the
     agent can't approve its own deploy with `curl`. The server also checks
     the user Authelia vouched for, and that a POST came from the page.
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

1. **A deploy restarts the service, even mid-turn.** pizza deploys pizza, so a
   deploy that changes the service restarts the agent that asked for it. The
   deploy survives that, being a unit of its own, but the turn doesn't. The
   restarted service tells the agent its turn was cut short, so it finds out
   how the deploy ended and carries on. It does that once: if that turn is
   cut short too, it waits for me.

   **Rejected: not restarting when the service changes.** A deploy then
   doesn't take effect until the service is restarted by hand. Restarting
   once the agent is idle would avoid the interruption altogether, and is
   worth building if it gets annoying.

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
1. **Proactive.** The chat server asks the agent, on a timer, to check
   whether master has moved; if it has, the agent proposes a deploy for me to
   approve.
1. **Earned autonomy.** Auto-approve the ordinary case (the tip passed CI, the
   host is healthy before and after) and keep the prompt for rollbacks and
   anything unusual.

## Open questions

1. **The real build.** The VM test fakes it: each fixture commit names a system
   already in the VM's store. `nix build` of the flake at the commit first runs
   for real on pizza.
1. **Evaluating on a Pi.** Whether norte's and sandy's caps leave the
   evaluation enough, and how slow it is, is untested until the first deploy.
1. **Memory and history.** The hosts' journals are the record of what was
   deployed. Whether the agent's own notes between sessions are worth having
   is something to find out by using it.
