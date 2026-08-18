# Agent PRs

**Status: proposal, nothing here is implemented.** Builds directly on
[`forgejo.md`](forgejo.md), which is implemented as far as
`nixos_modules/forgejo.nix` and `nixos_modules/forgejo-github-mirror.nix` go —
but its "Agent workflow" section is not, and this document supersedes it.

## Goals

1. Coding agents propose changes as Forgejo PRs rather than pushing to `master`
   or leaving a `slop` remote for me to go fetch.
1. Review happens by commenting on the PR. A comment causes the agent to act
   without me opening a terminal or returning to a session.
1. **One session spans the whole life of a change** — the initial design
   discussion, the first push, and every review round. Not a fresh agent per
   comment that has to rediscover the intent from the diff.

Goal 3 is the one that constrains the design, and it's worth being explicit that
it's a preference rather than a requirement: a stateless
agent-that-reads-the-PR-and-acts is simpler, and it survives here only as the
recovery path (decision 3).

## Background

### What exists

- `nixos_modules/forgejo.nix` — Forgejo 16.0.2 on `pizza`, canonical for
  `boxen`. Authelia forward-auth over the whole vhost *and* OIDC inside Forgejo;
  git over Forgejo's own SSH server on a tailnet-only port.
- `nixos_modules/forgejo-github-mirror.nix` — the backup, as a systemd timer per
  repo rather than a Forgejo push mirror, so a broken mirror trips
  `HostSystemdServiceCrashed`.
- `nixos_modules/slopbox.nix` + `tf/slopbox` — an Incus VM built for letting
  agents run loose. Persists state across `nixos-rebuild`; full rebuilds are
  rare.
- `packages/slopclone` — the current mechanism, made obsolete by this.
- `hm_modules/agent-host-context.nix` — always-on guidance delivered to every
  agent's memory file. The discovery mechanism for anything added here.

Not present, and needed: the `slopbot` identity, any reconciliation of per-repo
Forgejo state (webhooks, branch protection, collaborators — `forgejo.md`
decision 9, never written), Actions (`actions.ENABLED` is unset and there is no
runner), and anything that runs an agent unattended.

### Claude Code session mechanics

The facts the design leans on, all from `claude --help` and
`~/.claude/projects/` on `chungito`:

- Transcripts live at `~/.claude/projects/<cwd-slugified>/<session-uuid>.jsonl`.
  **Sessions are keyed by working directory**, so resuming one means being the
  same user, in the same directory, on the same host. This is what forces
  decision 2.
- `--session-id <uuid>` chooses the id up front; `-r/--resume <uuid>` with `-p`
  appends a turn non-interactively. Existing ids are UUIDv5, so deriving one is
  with the grain.
- `--from-pr <number|url>` resumes "a session linked to a PR". Upstream's model
  is already one session per PR; presumed GitHub-only, so not usable here, but
  it's evidence that goal 3 is the intended shape rather than a fight.
- `--permission-mode bypassPermissions` for unattended runs.
- `--input-format stream-json` accepts messages on stdin in realtime — a
  genuine channel into a resident session. Rejected in decision 5.
- `--environment ccpool_...` creates a *cloud* session that runs on a
  self-hosted environment. Unverified and potentially significant; see open
  questions.

## Decisions

1. **Changes arrive by AGit from a `slopbot` user, with `master` protected.**
   Unchanged from `forgejo.md` decision 8: the agent needs no branch write
   access and leaves no branch litter. Re-pushing a topic updates the PR in
   place and records the old and new heads, which the UI renders as a comparison
   between what I reviewed and what's there now. The security property is a
   branch protection rule, not trust.

   Verified against the live instance. Note that an update **requires
   `-o force-push=true`**: without it, a re-pushed topic whose commit was
   amended is rejected with "the tip of your current branch is behind its remote
   counterpart". Iterating on a change is the normal case here, so `slop-pr`
   passes it always.

1. **The session lives in the agent VM, from the first turn.** Transcripts are
   keyed by working directory, so a session can only span my design discussion
   and the daemon's review turns if both happen in the same directory as the
   same user on the same host. Initiation therefore moves into the VM: I ssh in
   and work there, and my terminal is only a client.

   The cost is that my editor and local tooling sit on the far side of an ssh
   hop. Accepted, because the whole point is to make development async — if I
   care about the build time or the editor, I'm doing it wrong.

   Corollary: **one user in the VM**, used both by me interactively and by the
   daemon. Splitting it into `me` and a service user gives two disjoint
   transcript stores and permission friction, which defeats decision 3.

1. **One session per change, keyed by the AGit topic, as UUIDv5.** The topic is
   chosen before the PR exists, survives every patchset, and is recoverable from
   the PR — the only key that spans discussion, PR and versions. A PR number
   can't be it: sessions predate PRs.

   Recovery is from `head.label`, which reads `<pusher>/<topic>` — the account
   that pushed, *not* the repo owner — and **not** from `head.ref`, which is
   only ever `refs/pull/<n>/head` for an AGit PR. Verified against the live
   instance, where the same topic produced `brendan/...` pushed by me and
   `slopbot/...` pushed by the agent. Consumers must strip the prefix rather
   than assume a username.

   `session_id = uuid5(NS, "<repo>:<topic>")` means there is **no PR-to-session
   mapping to store**: the handler derives the id from the PR in front of it.
   Create and resume become the same code path, since a missing transcript is
   just the case where the id has no session yet.

   **The fresh-session path still has to work**, as the recovery case: if the
   transcript is gone, the handler starts a new session with a briefing rendered
   from PR state (body, unresolved threads with file/line/hunk, comments since
   the last `slopbot` push). This is the fallback, not the design — but it has
   to be built, because it's what happens after a VM rebuild, and it's the only
   thing standing between "transcript lost" and "change abandoned".

1. **Trigger: any comment from `brendan` on a PR labelled `agent`.** No magic
   mention word — "comment on the PR and it happens" is the goal. The label
   scopes it so an ordinary PR isn't hijacked, and it goes on at creation time
   (`slop-pr`), so it must exist from P0 even though nothing consumes it until
   P1. Retrofitting labels onto already-open PRs is annoying.

   Comments by `slopbot` are ignored, or the thing loops.

   **The author allowlist is the authorization boundary.** Not the label, not
   the trigger word: the reason a stranger can't drive an agent with
   `bypassPermissions` is that only my comments count.

1. **Trigger transport: a Forgejo webhook, delivered to a handler *inside* the
   VM.** The agent VM is on `pizza` (decision 6), which is always on, so a
   webhook is *correct* and not merely fast — the argument for polling was that
   Forgejo doesn't meaningfully retry a delivery into a sleeping workstation, and
   that argument dies with the always-on host.

   The handler runs in the VM, alongside the agent, as the same user. This is the
   difference between "the handler starts a local process" and "the handler
   reaches across a boundary to start a process", i.e. between a systemd unit and
   an `ssh`/`incus exec` invocation whose credentials and failure modes I'd have
   to design. Nothing is gained by putting it outside, because **there is no
   privilege to separate**: the agent must hold `slopbot`'s SSH key to push and
   `slopbot`'s API credential to reply to reviews, so a handler in the VM adds
   only the webhook HMAC secret to what an escaped agent could read — and the
   most that buys is the ability to forge a trigger for a run it could have
   started directly anyway.

   What the VM does *not* get is anything belonging to `brendan` or to `pizza`:
   the deploy keys, the GitHub mirror key, the Forgejo admin credential, and the
   bootstrap oneshot of decision 10 all stay on the host.

   **There is no host-to-guest plumbing to build.** `slopbox` is already a
   tailnet node in its own right (`100.92.183.118` today, alongside its
   `incusbr0` address), so the webhook URL is just `http://slopbox:<port>/…` and
   Forgejo makes an ordinary HTTP request to it. Incus NAT constrains the guest's
   *outbound* path; it has nothing to say about the host, or any other tailnet
   member, connecting *in*.

   If I'd rather the handler weren't reachable from the whole tailnet, the
   alternative is to listen only on the `incusbr0` address so that only `pizza`
   can reach it — which needs a static address on that NIC, since the bridge
   hands out DHCP leases. Either way the HMAC signature is what actually
   authenticates the sender, and it's cheap enough to keep in both cases.

   The one genuinely new bit of plumbing is agenix in the guest — its SSH host
   key already persists, so it can be an agenix target like any other host.

   A catch-up sweep on handler start covers a restart or deploy landing
   mid-review; a low-frequency catch-up timer covers the rest (decision 9).

   **Rejected: a resident `claude -p --input-format stream-json` process per open
   PR**, fed by the webhook. It's the purest form of goal 3 — a real channel,
   no reload between turns — but it's a supervisor to write, a process per open
   PR holding context indefinitely, and interactive takeover still means killing
   it and resuming. `-p --resume` per comment buys the same continuity with no
   daemon-held state.

   **Rejected: MCP as the trigger.** MCP provisions tools to a *running*
   session; it has no way to push a message into an idle one. It is the right
   answer for the other half — the session's Forgejo tools — see the design.

   **Rejected: cross-session messaging / Remote Control as the trigger.** Those
   exist but are account- and cloud-mediated and need an already-running,
   attached session. A webhook on `pizza` can't dial into one.

1. **The agent runs in an Incus VM on `pizza`, not on `chungito`.** Always-on
   beats fast: the workflow is asynchronous, so a slow agent is merely slow,
   whereas an agent on a sleeping workstation is a broken feature. Nobody is
   watching a progress bar.

   This does mean a second Nix store on an 8 GB box with 68 G free (decision 7),
   which is a real cost and directly contradicts `forgejo.md` decision 6's
   reasoning about where Nix builds belong. The difference is that CI must be
   fast to be useful and an agent needn't be.

   If the store or the RAM turns out to be the problem, the escalation is *not* a
   bigger VM: it's running the agent natively on `pizza` in a systemd sandbox and
   tolerating the weaker isolation, or finding a safe way to share the host's
   store.

1. **The agent builds in the VM, slowly, and lives with it.** It runs
   `nix flake check` like I would. Elaborate schemes for pushing builds
   elsewhere — CI as the agent's only feedback channel, remote builders — buy
   speed at the cost of the agent not being able to check its own work until
   after it has published it, which is the wrong trade for an async workflow
   where nobody is waiting.

   The binding constraint is disk rather than time: `nix flake check` builds
   every `x86_64` host closure in the flake, and `pizza` has 68 G free for both
   Forgejo and this. If that becomes the problem, the escalations are in
   decision 6, plus the option of pointing the VM at `pizza`'s store as a
   substituter so the duplication is bounded to what the VM actually builds.

   Consequence: **Actions is no longer load-bearing.** It stays worth having as
   independent verification and as a merge gate, but it isn't the agent's route
   to knowing whether its change works, so it drops down the priority list.

1. **`bypassPermissions`, with safety entirely outside the Claude client.**
   Prompting a nonexistent human to approve a tool call is theatre. What
   actually bounds the damage:

   - the VM boundary — filesystem and process containment, and in particular
     nothing of `brendan`'s or `pizza`'s inside it (decision 5);
   - `slopbot`'s credential cannot push `master` (decision 1), so the worst
     in-repo outcome is a bad PR version, which is cheap;
   - only my comments trigger a run (decision 4).

   Note the third of those is a boundary against *other people*, not against the
   agent: everything a forged trigger could cause is something the agent could
   already do with the credentials it must hold. The honest statement is that
   inside the VM there is one trust domain, and the containment is the VM.

   **What is *not* bounded is the network.** `slopbox` is a tailnet member, not
   something hiding behind NAT: it can reach every service in the homelab
   directly, and other tailnet nodes can reach it. VM isolation buys filesystem
   and process containment, not network containment, and this is the weakest part
   of the whole design. The lever, if it matters, is Tailscale ACLs and/or egress
   filtering down to Forgejo and `api.anthropic.com`. Deferred to P1,
   deliberately and with eyes open.

1. **A live session means manual mode — and deferral, not loss.** Nothing stops
   two writers appending to one transcript, so the handler takes an flock on the
   session. Rather than arbitrating:

   - session process alive → the comment is left unhandled and picked up later;
   - no live session → comments arrive as `-p --resume` turns.

   The important part is that a comment arriving while I'm attached must not be
   dropped. That requires separating **seen** from **handled**: the handler only
   advances the handled marker after a run actually addresses a comment, so a
   deferred comment is still outstanding afterwards. And something has to come
   back for it, which means a **low-frequency catch-up timer** — every few
   minutes, process anything outstanding whose lock is free.

   So polling returns, but demoted: the webhook is the fast path, the timer is
   the thing that makes the design correct. It also subsumes the missed-delivery
   and restart cases, which is a good sign it belongs there. `slop` can poke the
   handler when a session exits, to cut the deferred latency from minutes to
   seconds, but that's a nicety and not the mechanism.

   Handling the same comment twice — because I addressed it myself while attached
   and the handler then replays it — is benign *because it's the same session*:
   the agent's own context shows it already did the work, and it can say so.
   Session continuity turns what would be a correctness problem into a
   redundant turn.

   Residual failure mode: a session left running by accident silently disables
   the automation, so the handler should say so in the PR ("live session
   attached, deferring") rather than being quiet about it.

1. **Forgejo runtime state is reconciled from Nix.** `forgejo.md` decision 9,
   finally needed: the `slopbot` user, its SSH key, collaborator lists, `master`
   protection, the `agent` label and the webhook are all per-repo rows in
   Forgejo's DB, and this repo tries not to have those. A oneshot after
   `forgejo.service`, in the shape of the existing `forgejo-oidc` unit.

   This also matters because `forgejo.md` decision 7 (no backups, the GitHub
   mirror is the copy of record) is explicitly load-bearing on the bootstrap oneshot:
   losing `/var/lib/forgejo` is only survivable while this state is rebuildable
   from code.

   The unit authenticates to the API as a **dedicated `bootstrap` admin account**
   whose password is in agenix. The CLI covers users and passwords but not
   collaborators, branch protection or labels, and those endpoints need an
   account that can authenticate. A token would be the obvious alternative and
   is a dead end: `forgejo admin user generate-access-token` can neither replace
   nor delete a token, so a fixed name collides on the second run, and the
   endpoints that could clean one up are basic-auth-only - which `brendan`
   cannot do with `ENABLE_INTERNAL_SIGNIN` off. An account whose credential
   comes from agenix is declarative, idempotent and revocable by deleting it.

1. **Credentials from agenix, both sides declarative.** `slopbot` needs to *read*
   the API, and Forgejo access tokens can only be minted at runtime — they can't
   come from agenix, and shipping one from `pizza` to the VM reintroduces exactly
   the non-declarative state decision 10 removes. So: **API basic auth**, with a
   password from agenix set by the bootstrap unit. Unverified; see open
   questions.

   The Anthropic credential (`claude setup-token` output, or an API key) expires
   and has to be rotated by hand. Annoying and unavoidable; the goal is to make
   rotation a one-liner, not to solve it.

1. **Forgejo's own auth faces the internet; the Authelia forward-auth in front
   of it goes away.** Something outside `pizza` has to reach the API — the agent
   replies to reviews and applies labels, and later reads CI results — and today
   `HTTP_ADDR` is loopback-only while the Caddy vhost gates *everything*,
   `/api/v1` included, behind an Authelia session that no API client can obtain.

   The alternatives were binding Forgejo's HTTP port on the tailnet, or exempting
   `/api/v1` from `forward_auth` in Caddy. Both work. Neither is as simple as
   admitting that Forgejo is a forge, that forges are internet-facing software,
   and that Codeberg runs this exact code on the open internet. Accepted risk:
   pre-auth vulnerabilities now matter, where before they were reachable only
   from the tailnet.

   Two things make that tolerable rather than reckless. `REQUIRE_SIGNIN_VIEW` is
   already on, so there is no anonymous browsing surface. And of the two CVEs
   `forgejo.nix`'s comment cites as the reason for the belt-and-braces posture,
   the admin-impersonation one is only exploitable with
   `ENABLE_REVERSE_PROXY_AUTHENTICATION`, which this deployment has always
   refused to use.

   Patch latency is the other residual: Codeberg patches within hours of
   disclosure and this instance patches whenever I next run `nix flake update`
   and deploy. That is a real gap, but it is not a Forgejo problem — it applies
   to every service behind the IAP — so it wants a systematic answer (something
   that watches security news and tells me) rather than a Forgejo-shaped
   exception. Explicitly out of scope here, and explicitly not a reason to
   delay.

   **Every Authelia user gets in, and that's accepted.** `iap.nix` derives the
   access-control rule from `forwardAuth`, so dropping it turns the rule into
   `bypass` and `allowedUsers = [ "brendan" ]` must go with it (there's an
   assertion). With `ENABLE_AUTO_REGISTRATION` and `ACCOUNT_LINKING = "auto"`,
   every user in `users.json` can then log in and be auto-created as a
   non-admin Forgejo user. These are friends and family, `boxen` is already
   public on GitHub, and admin still follows the `admin` group — so the
   confidentiality delta is approximately zero.

   The consequence that does matter: **the trigger allowlist in decision 4 is
   now the only thing standing between a logged-in user and a
   `bypassPermissions` agent run.** It was always the authorization boundary;
   with a wider user base it stops being theoretical. If it ever needs
   narrowing, Authelia 4.39 supports per-client authorization policies
   (`identity_providers.oidc.authorization_policies`), which is also the answer
   to the "(I dunno how)" in `iap.nix`'s assertion message.

   Consequences beyond this document: `forgejo.nix`'s long comment argues for
   exactly the posture being abandoned and must be rewritten rather than left to
   contradict the code. The git-over-HTTP surface becomes internet-facing too,
   which is what `forgejo.md` decision 4 wanted to avoid but also what makes
   Actions checkout work without tailnet access later.

## Design

### Naming

`slopbot` is the Forgejo user. The VM is `slopbox` if the existing one is reused,
which it should be — it exists for this.

### Commands

**Nothing here does SSH.** I ssh into the VM myself; these run inside it, so they
are ordinary local commands in the VM's configuration rather than wrappers on
`chungito` that have to know how to reach it. That also means they and the
handler invoke `claude` identically, instead of one path going through a remote
shell.

- **`slop <topic>`** — the single entry point, from inside the VM. Creates the
  workspace if needed, then `tmux new -A -s <topic>` around
  `claude --session-id $(uuid5 "<repo>:<topic>")`. Idempotent by construction:
  attach-or-create at the tmux level, resume-or-create at the session level, so
  there's no separate "attach" command and no way to accidentally start a second
  session for one change.

  tmux is load-bearing rather than a convenience — see Remote Control below.

- **`slop-pr`** — from inside a workspace:
  `git push origin HEAD:refs/for/master -o topic=<topic> -o title=… -o description=…`,
  then one API call to apply the `agent` label. The topic comes from the
  workspace, so it matches the session id by construction.

The VM's `bjackman.agentHostContext` gets a paragraph pointing at `slop-pr`,
replacing the `slopclone` habit. Note this is the *guest's* home-manager
configuration (`hm_modules/slopbox.nix`), not `chungito`'s.

### Remote Control

Because `slop` keeps the process alive in tmux, connecting it with `/rc`
makes claude.ai and the phone app usable as the interface for the interactive
half — the VM already needs outbound HTTPS for the API, so there's no new
network path. This is why tmux is load-bearing rather than a convenience: RC
bridges a *running* session, and a session that dies with my ssh connection has
nothing to bridge.

What this doesn't give me is *creating* a session from claude.ai. Two possible
answers, in order of preference:

1. `--environment ccpool_...` — a cloud session that runs on a self-hosted
   environment. If an Incus VM can be registered as one, this is the sanctioned
   path and it's strictly better than everything below. Unverified.
1. **Forgejo as the initiation surface.** Because create and resume are one code
   path (decision 3), an issue can start a change: open an issue whose title is
   the topic, comment the request, and the handler starts a session on it. Then
   any browser can kick off work and claude.ai is optional. The only new logic
   is issue-title-to-topic and, later, promoting the result to an AGit push.
   Cheap, and it needs no Anthropic-side feature to exist.

Neither is P0.

### The handler

A service in the VM (decision 5), receiving webhook deliveries from Forgejo
directly over the tailnet:

1. Verify the webhook HMAC. Reject anything unsigned.

1. Filter: PR labelled `agent`, comment author `brendan`, author not `slopbot`,
   comment not already handled.

1. Coalesce: a review submitted with five inline comments is one run. Hold
   briefly, and serialize per change — one run at a time, re-checking for
   comments that arrived mid-run before exiting.

1. Take the session flock. If a live session holds it, mark the comment
   outstanding, say "live session attached, deferring" in the PR, and leave it for
   the catch-up timer (decision 9). **Do not advance the handled marker.**

1. Run locally: `claude -p --resume <uuid5> --permission-mode bypassPermissions`
   with the comment (and its file/line context) as the user turn. If no
   transcript exists, start a session with a rendered briefing instead.

1. The agent pushes with `-o topic=<topic>`, replies on the threads it addressed,
   resolves them, and reacts on the trigger comment.

1. Footer on every reply: the session id and the `slop <topic>` invocation, so
   taking over is a copy-paste.

1. Failure handling splits by kind, and **does not swallow anything**:

   - **The agent declined or couldn't do the job** — ambiguous comment, checks it
     couldn't make pass, a change it judged wrong. That's a normal outcome, not an
     error: comment and exit 0.
   - **The infrastructure failed** — Forgejo unreachable, credential rejected,
     Anthropic token expired, `claude` exited nonzero, push rejected unexpectedly,
     disk full. **Fail the unit**, after trying to post the log tail. That trips
     `HostSystemdServiceCrashed`, which is correct: these are all conditions I
     have to fix by hand, and expired-token-fails-loudly is exactly what makes
     decision 11's manual rotation tolerable.

   Suppressing a noisy-but-real alert belongs in the Prometheus configuration,
   not in an `exit 0` that makes the failure invisible. This matches
   `forgejo-github-mirror.nix`, which deliberately uses unit failure as its
   alerting mechanism.

### The agent's Forgejo tools

A Forgejo MCP server if a decent one exists, otherwise a small `fj` wrapper doing
authenticated `curl`. Either way the agent should not be improvising HTTP calls
against an API it half-remembers.

### Scope

- **P0** — `slopbot` and the bootstrap oneshot; `slop` and `slop-pr` in the VM;
  the `agent` label applied from day one. Review is by hand in the UI. This proves
  the AGit assumptions before anything is built on them.
- **P1** — the webhook, the handler and the catch-up timer: the actual review
  loop. Egress filtering decided here.
- **P2** — Actions on the `chungito` runner and `nix flake check` per PR version,
  as independent verification and a merge gate. No longer on the critical path
  (decision 7), so it happens if and when the manual gate annoys me.

## Gotchas and open questions

- **AGit and basic auth are verified** (Forgejo 16.0.2, live instance).
  `-o topic= / -o title= / -o description=` are accepted over SSH and populate
  the PR; updates need `-o force-push=true`; `flow: 1` marks the PR as AGit;
  `head.label` carries the topic. API basic auth works with
  `ENABLE_INTERNAL_SIGNIN = false`, so decision 11's credential story stands.
  Basic auth was exercised against Forgejo's own listener on `pizza`; through
  Caddy it is currently blocked by the forward-auth that decision 12 removes,
  which is worth re-checking once that lands.
- **Version history is a timeline event, not a patchset object.** Each push
  appears as a `pull_push` entry carrying `is_force_push` and the commit ids, so
  "what changed since I reviewed" is derivable — but there is no numbered
  patchset resource to fetch, and an agent wanting to know what it changed last
  round has to reconstruct it from that timeline.
- **Self-hosted cloud environments (`--environment ccpool_...`) are unverified**,
  as is `--teleport`, whose semantics I do not know at all. Both sit in the area
  that would let claude.ai create the initial session, so both are worth 20
  minutes before conceding that limitation.
- **Continuity has a half-life.** Context grows monotonically across a long
  review and `--autocompact` eventually summarizes the early turns, so the design
  discussion is verbatim for a while and then isn't. Graceful, but it means
  anything load-bearing still belongs in the PR description or a commit message
  rather than in the session's memory.
- **Transcripts are state.** Low-stakes given the VM persists across
  `nixos-rebuild` and full rebuilds are rare, and decision 3's fallback covers
  the loss. Worth not making it *more* load-bearing than it already is.
- **Agent PRs aren't in the GitHub mirror.** `refs/pull/*` is a hidden ref
  namespace GitHub refuses, so the review queue is replicated nowhere
  (`forgejo.md` decision 7 accepted this). With sessions in the loop the
  regeneration cost is now "re-run the agent *and* lose the discussion", which is
  higher than it was — but still not high enough to justify backups.
- **Whether Forgejo webhooks fire on the events needed** — issue comment, review
  submitted, review comment — with enough context to identify the PR and the
  comment. Almost certainly yes; the handler's filter depends on the payload
  shape, so check before writing it.
- **Store size in the VM is the thing most likely to bite** (decision 7). A full
  `nix flake check` closure set on a box with 68 G free, shared with Forgejo,
  wants measuring before it's trusted — and a store that fills up is a disk alert
  on `pizza`, i.e. it degrades into *my* problem rather than the agent's. The
  root disk size is already an explicit knob in `tf/slopbox/slopbox.tf` (512 G
  today, on a workstation), so capping it so the guest can only ruin itself is a
  one-line change rather than new machinery. `limits.memory` in the same file says
  `32GiB` and obviously can't stay that way on an 8 G host.
- **Agenix in the guest is new plumbing.** The VM's host key persists, so it can
  be an agenix target, but nothing in this repo does that for a `slopbox`-shaped
  machine yet. It also means adding the guest to `secrets/secrets.nix`, i.e. the
  VM can decrypt exactly the secrets listed for it and no others.
- **The guest is a tailnet node, which is what makes the webhook trivial and the
  isolation weak.** Both follow from the same fact, and it's worth holding them
  together: the reason no plumbing is needed (decision 5) is exactly the reason
  the containment story is thin (decision 8). Tailscale ACLs are the tool for
  narrowing it without giving up the reachability the webhook depends on.
- **Two humans.** Everything above assumes exactly one reviewer. If someone else
  ever needs to drive an agent, decision 4's allowlist is the place it changes,
  and the blast radius of getting it wrong is `bypassPermissions` on a tailnet
  node.
- **Patch currency is now a security property** (decision 12), and the design
  deliberately declines to solve it. If the systematic answer never materialises,
  this is the assumption that quietly stops holding.
- **Pushing a head the pull request already has is rejected**, with "The new
  commit is the same as the old commit". So a tool that pushes and then does
  API work can't treat the push as unconditional: it has to compare the PR's
  `head.sha` first, or a re-run aborts before the API work and leaves the PR
  half-configured. Verified end-to-end.

## Implementation notes

`slop` stays a shell script: it execs `tmux` and `claude` and has nothing to
decide. `slop-pr` is Go, in `packages/slop-tools`, sharing an
`internal/forgejo` client with the handler that P1 will add as a second command
in the same module — the handler needs the same lookups (find the pull request
for a topic, read its comments, reply, label) and two implementations of that
would rot apart.

The client is hand-rolled against `net/http` rather than using a Gitea SDK.
Half a dozen endpoints don't justify vendoring an SDK that tracks a forge
Forgejo has diverged from, and with no external dependencies `buildGoModule`
takes `vendorHash = null`, so there's no hash to regenerate when anything
upstream moves.

The distinction Go buys over the shell version, and the reason for the port:
`slop-pr` exits 1 when nothing was published and 2 when the change was pushed
but the pull request couldn't be finished (labelled, assigned). The shell
version conflated those, and in practice that meant a successful push followed
by a failed lookup left an unlabelled pull request that the P1 handler would
ignore, reported as a plain failure.

- **Forgejo won't call a tailnet address without being told to.**
  `webhook.ALLOWED_HOST_LIST` defaults to `external`, meaning public addresses
  only, so delivery to the handler fails with "webhook can only call allowed
  HTTP servers" — and fails *silently* from the reviewer's point of view, since
  the only evidence is in Forgejo's log. The sweep timer hides it by doing the
  work a few minutes later, which makes this exactly the kind of breakage that
  can sit unnoticed.
- **Webhook event names are groups, not the stored values.** Asking for
  `pull_request_review_approved` and friends leaves a hook subscribed to
  nothing: the API accepts `pull_request_review`, then reports the expanded
  list back. Unrecognised names are dropped without an error, so the create
  call succeeds and the hook simply never fires.
- **Claude Code needs a POSIX shell, and systemd hands it my login shell.**
  With `User=brendan`, systemd sets `$SHELL` from passwd, which is fish, and
  every Bash tool call fails with "No suitable shell found". The agent noticed,
  fixed the file it was asked to fix, and reported that it couldn't commit -
  which is the behaviour this design wants, but the unit has to set `SHELL`.
