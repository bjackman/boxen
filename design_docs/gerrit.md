# Gerrit

**Status: proposal, nothing implemented.** Supersedes the review half of
[`agent_prs.md`](agent_prs.md), which is implemented and working; the parts of
it about sessions, workspaces and the handler's shape survive this change
almost unaltered.

## Goals

1. Replace Forgejo with Gerrit as the canonical forge, because Forgejo's code
   review is unpleasant to use and Gerrit's isn't.
1. Keep everything `agent_prs.md` bought: one Claude session per change,
   spanning design discussion and every round of review; review from a browser
   without returning to a terminal.
1. Don't lose the GitHub mirror, which is the only backup.

## Background

### Why this is worth the churn

The agent loop works. What doesn't is *reviewing* — and since the entire point
of the exercise is that I review changes from the forge, a review UI I avoid
using makes the whole thing pointless. This is a change of substrate, not of
design: it's the same workflow with a forge whose review model is the one I
already think in.

It's worth being clear-eyed that this throws away real work. `internal/forgejo`,
`slop-pr`'s labelling and assignment, the webhook plumbing and the
`forgejo-bootstrap` unit are all Forgejo-shaped. What survives is everything
that turned out to be hard: the session-per-topic identity, the sweep loop, the
adoption rule, the deferral rule, the exit-code split, and the workspace layout.

### Gerrit is a better fit than Forgejo was

Not just familiar — structurally closer to what this design already reaches for:

- **AGit was modelled on Gerrit.** `git push origin HEAD:refs/for/master` is
  already what `slop-pr` does. The push side barely changes.
- **Patchsets are native.** Forgejo records an update as a force-push timeline
  event and the UI infers a comparison; Gerrit has numbered patchsets and
  between-patchset diffs as a first-class concept. That's the review experience
  the original design asked for and only approximated.
- **Reviews are batched by construction.** Comments are drafts until published
  as a review, so "six comments, one agent run" is what the event stream hands
  you, rather than something the handler has to coalesce with a timer.
- **The automation interface is SSH.** `gerrit query`, `gerrit review`,
  `gerrit set-topic` and friends run over the same SSH transport as git, keyed
  by the same key. No API password, no basic auth.
- **`stream-events` replaces the webhook**: a long-lived SSH connection
  emitting JSON. No HMAC secret, no inbound port on the agent VM, no
  `ALLOWED_HOST_LIST` to get wrong.
- **"Can't push to master" is native.** Gerrit's permission model grants push
  to `refs/for/*` separately from `refs/heads/*`, so the agent's inability to
  land its own changes is the default arrangement rather than a branch
  protection rule bolted on afterwards.

### What nixpkgs provides

`pkgs.gerrit` is 3.13.8 and `services.gerrit` exists, with `jvmHeapLimit`
(default `1024m`), `jvmOpts`, `builtinPlugins`, `plugins`, `settings`,
`serverId` and `replicationSettings`.

### What this costs

- **A JVM on `pizza`.** It has 7 G of RAM, ~5 G available, and also runs
  Jellyfin, Postgres, Caddy, Authelia and Prometheus. Gerrit at the default 1 G
  heap plus JVM overhead is a bigger resident footprint than Forgejo's few
  hundred MB. This is the main risk in the whole proposal.
- **CI gets further away.** `agent_prs.md`'s P2 was Forgejo Actions on the
  `chungito` runner. Gerrit has no built-in CI; the equivalent is a verifier
  that watches `stream-events`, runs `nix flake check` and votes `Verified`.
  That's more work, though a better shape - and the agent already builds
  locally (P0 decision 7), so nothing regresses today.
- **Issues and the label/assignee vocabulary go away.** No issue tracker is in
  use, so the real loss is the `agent` label and the assignee, both of which
  have Gerrit equivalents (hashtag, reviewer) that fit better anyway.

## Decisions

1. **Gerrit on `pizza`, Forgejo removed once the migration is verified.** Same
   reasoning as `forgejo.md` decision 2: it's where the IAP, the reverse proxy
   and every other service already live, and it's always on. Running both
   permanently would double the footprint on the box least able to afford it.

   Keep `/var/lib/forgejo` and the module for a grace period after cutover, so
   that "Gerrit turned out to be worse" is a revert rather than a recovery.

1. **Authelia goes back in front, and Gerrit trusts the proxy.**
   `auth.type = HTTP`, `httpd.listenUrl` on loopback only, Caddy `forward_auth`
   with `allowedUsers = [ "brendan" ]`. This **reverses `agent_prs.md` decision
   12**, which put Forgejo's own login on the public internet.

   That decision existed for one reason: the agent needed the REST API from
   outside `pizza`, and no API client can follow Authelia's login redirect.
   Gerrit's automation is SSH, so the reason evaporates and the pre-auth surface
   goes back behind Authelia. Strictly better than where we are now.

   The corollary is that header-trusted auth makes Gerrit's HTTP port
   *equivalent to an admin session* for anything that can reach it - the exact
   failure mode `forgejo.md` decision 4 rejected. It's acceptable here only
   because the listener is on loopback and Caddy is the sole path. If that ever
   stops being true, this decision is wrong.

1. **The agent authenticates with an SSH key and nothing else.** One credential
   (`slopbot-ssh-privkey`, which already exists), used for git *and* for the
   query/review commands. `slopbot-forgejo-password` and
   `slopbot-webhook-secret` are deleted, along with the basic-auth machinery
   they justified.

1. **Session identity stays keyed on the topic.** `uuid5("<repo>:<topic>")`,
   unchanged, so `slop` and the session-continuity property carry over
   untouched. Gerrit topics group a multi-commit series exactly as AGit topics
   do.

   **Rejected: keying on Change-Id.** It's the more intrinsic identifier and
   needs no push option, but a series has one per commit, so it identifies a
   commit rather than a change-in-progress. The topic is what spans the work.

1. **`stream-events` for latency, a periodic sweep for correctness.** The same
   split as today, and for the same reason: the stream is a long-lived SSH
   connection that can drop, and a dropped stream is invisible. The lesson from
   the `ALLOWED_HOST_LIST` bug is that the sweep is what makes the system
   correct and the push channel is only an optimisation - so the sweep stays
   even though the stream is more reliable than a webhook.

1. **Work is batched per topic, and held until the topic goes quiet for two
   minutes.** Two separate problems, both arising from reviewing a series:

   **Grouping.** A multi-commit series is several Gerrit changes sharing a
   topic, and the topic is the session. Gathering pending comments per *change*
   would run the agent once per reviewed commit, each run seeing a fraction of
   the feedback and each producing its own patchset and reply - against one
   conversation that would then contradict itself. So the unit of work is the
   topic: every unhandled comment across every change in it goes into one run.

   **Timing.** Publishing reviews on four changes takes a minute or two of
   clicking, so grouping alone isn't enough - the first published review would
   fire immediately and the rest would arrive mid-run. Hence a debounce: a topic
   is eligible only when its newest unhandled comment is at least two minutes
   old.

   Expressed as *eligibility by age* rather than as a countdown timer, which
   matters more than it sounds: it's stateless, it behaves identically whether
   the wake came from `stream-events` or from a sweep, and a restart mid-window
   loses nothing because the age is recomputed from the comment timestamps. A
   timer would have to be persisted or forgotten.

   The window slides: comments arriving during it push the deadline out, which
   is the intended behaviour while I'm still working through a series. That does
   mean a long unbroken stream of comments defers indefinitely. Left uncapped on
   purpose - "still reviewing" is exactly when the agent should wait - but if it
   ever feels wrong, a maximum hold is the escalation.

   When a topic is deferred for freshness the handler schedules a wake for when
   it will age out, rather than leaving it to the next sweep; otherwise the
   effective latency is the sweep interval rather than the window.

1. **Project configuration is reconciled from Nix, via `refs/meta/config`.**
   Gerrit keeps ACLs in a `project.config` file on a git ref, which is a better
   fit for this repo than Forgejo's database rows were: the bootstrap unit
   fetches the ref, rewrites the file from a Nix-defined attrset, and pushes it
   back only if it changed.

   The grants that matter: I get `Push` on `refs/heads/*` and `Submit`;
   `slopbot` gets `Push` on `refs/for/refs/heads/*` (create change) and nothing
   on `refs/heads/*`.

1. **The GitHub mirror stays a systemd timer, repointed at Gerrit's repo path.**
   Gerrit's `replication` plugin would do it, but `forgejo-github-mirror.nix`'s
   comment records the reason it's a unit: a broken mirror fails the unit and
   trips the existing alert, where a plugin reports failure into a web UI I
   won't look at. That reasoning is unchanged, and the module is three lines
   from working - `cfg.stateDir/repositories/brendan/boxen.git` becomes Gerrit's
   `git/boxen.git`.

1. **`slop` is unchanged; `slop-pr` and the handler are ported.** The workspace
   layout, tmux behaviour, session id derivation and resume-vs-create logic are
   forge-agnostic and stay. `internal/forgejo` is replaced by `internal/gerrit`
   speaking SSH; the handler's sweep, adoption, deferral and exit-code logic are
   untouched.

## Design

### `nixos_modules/gerrit.nix`

```nix
services.gerrit = {
  enable = true;
  serverId = "...";                      # uuid, fixed forever
  listenAddress = "127.0.0.1:${toString port}";
  jvmHeapLimit = "1024m";
  builtinPlugins = [ "download-commands" "hooks" ];
  settings = {
    gerrit.canonicalWebUrl = url;
    auth.type = "HTTP";                  # Caddy + Authelia set the header
    sshd.listenAddress = "*:29418";
    receive.enableSignedPush = false;
    change.enableAttentionSet = true;
  };
};
```

with `bjackman.iap.services.gerrit = { inherit port; forwardAuth = true; allowedUsers = [ "brendan" ]; }` - the plain, boring IAP setup that Forgejo
couldn't use.

SSH is on 29418, firewalled to `tailscale0` exactly as Forgejo's is now.

### Accounts and bootstrap

Gerrit has no `admin user create` CLI equivalent that works before the first
login; with `auth.type = HTTP` the first authenticated user becomes an
administrator and subsequent users are created on first request. So the
bootstrap unit's job is smaller than `forgejo-bootstrap`'s:

- create the `slopbot` service account and register its public key
  (`gerrit create-account slopbot --ssh-key ...`, over SSH as admin);
- reconcile `refs/meta/config` for the project;
- create the project if absent (`gerrit create-project`).

All of it over SSH, using an admin key held only on `pizza`. That replaces the
`bootstrap` admin account and its agenix password.

### `slop-pr`

```
git push origin HEAD:refs/for/master \
    -o topic=<topic> \
    -o r=brendan \
    -o hashtag=agent
```

Push options replace three API calls: the reviewer is the assignee equivalent
and puts the change in my dashboard, and the hashtag is the `agent` label
equivalent that tells the handler this change is agent-driven. `--force` has no
analogue and needs none - Gerrit accepts a new patchset for the same Change-Id
as a matter of course, so the "same commit as the old commit" special case
disappears.

`Change-Id` requires the `commit-msg` hook in the workspace; `slop` installs it
at clone time, which is the one line it gains.

### The handler

Same structure, different transport:

- **Trigger:** `ssh gerrit gerrit stream-events`, reading JSON lines, waking the
  sweep on `comment-added` events. Reconnect with backoff; never treat a live
  stream as proof of health.
- **Sweep:** `gerrit query --format=JSON status:open hashtag:agent --current-patch-set --comments`, comparing comment timestamps against the
  handled state, then grouping the pending comments by topic.
- **Batch and hold:** a topic runs only once its newest unhandled comment is
  older than `--debounce` (2m). Otherwise the handler schedules a wake for the
  moment it ages out and moves on. Comments from several changes in one topic
  arrive at the agent as one prompt, labelled by change and file.
- **Reply:** `gerrit review <change>,<patchset> --message '...'`, optionally
  with a label vote. For a multi-change batch the reply goes on the change whose
  comments prompted it - or on each of them, which is a decision to make when
  it's built rather than now.
- **Everything else unchanged:** adoption on first sighting, deferral while a
  tmux session is attached, the reply-is-the-agent's-final-message rule, and the
  exit-1/exit-2 split.

### Migration

1. Stand Gerrit up alongside Forgejo; both are small enough to coexist briefly.
1. `git push` `boxen` into Gerrit, verify history matches.
1. Repoint `forgejo-github-mirror` at Gerrit's repo path; verify GitHub receives
   a push. **Do not proceed until the backup demonstrably works.**
1. Port `slop-tools`, deploy, run one throwaway change end to end - propose,
   review, iterate, submit.
1. Repoint my own clones and the VM's.
1. Disable Forgejo, keeping `/var/lib/forgejo` and the module for a grace
   period.

## Gotchas and open questions

- **Whether `gerrit query --comments` returns inline file comments** with path
  and line, or only patchset-level messages. The handler needs file anchoring to
  give the agent useful context, and this determines whether SSH really is a
  complete automation interface. If it isn't, the fallback is the REST API -
  which under `auth.type = HTTP` means working out how a service account
  authenticates without a browser, and that could unpick decision 2. **Verify
  this first; it's the load-bearing unknown.**
- **JVM footprint on a 7 G box shared with Jellyfin.** 1 G heap is the default,
  not a measurement. Worth watching RSS under real use before trusting it, and
  worth knowing that Jellyfin transcoding and Gerrit indexing at the same time
  is the case that will hurt.
- **`serverId` is permanent.** It's baked into NoteDb records; changing it later
  orphans review metadata. Generate once, commit it, never regenerate.
- **First-login-becomes-admin is a bootstrapping trapdoor.** With `auth.type = HTTP`, whoever authenticates first is an administrator. That must be me,
  through Caddy, before anything else can reach the port.
- **Review metadata lives in git, which changes the backup story for the
  better.** Unlike Forgejo, where `refs/pull/*` couldn't be mirrored and the
  review queue had no backup, Gerrit keeps changes and comments in
  `refs/changes/*` and `refs/meta/*`. Whether GitHub will accept those refs is
  unverified - `refs/changes/*` isn't a hidden namespace there, so it may just
  work, which would mean the mirror finally covers reviews too.
- **Losing Forgejo means losing the Actions plan.** If CI matters more than the
  review UX, that's an argument for staying. It doesn't, today, because the
  agent verifies its own work locally.
- **The `agent` hashtag has the same retrofit problem the label did**: changes
  created before the handler understands hashtags won't have one.
