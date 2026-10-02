# Gerrit CI

**Status: implemented.** [`gerrit.md`](gerrit.md) left CI as the one thing the
migration lost, on the grounds that the agent builds locally so nothing
regressed. This is the plan to get it back.

## Goals

1. `nix flake check` runs on every patch set of `boxen` and votes `Verified`,
   and a change can't be submitted without that vote.
1. When it fails, the whole build log can be read. A plain text HTTP endpoint
   is enough; the log must not be limited to what fits in a review message.
1. The smallest system that does both. Not a CI platform.

Nice to have, and not goals: rich presentation inside Gerrit - a Checks tab, a
per-job breakdown, links from the diff. More than one job, or more than one
project.

Added later: changes that are ready are submitted without anyone pressing the
button. See decision 10.

## Background

### What the check actually costs

Measured on `slopbox`, warm store, against `flake_modules/checks.nix` - which
builds every NixOS `toplevel` plus every Home Manager activation package:

| | wall | peak RSS |
| --- | --- | --- |
| evaluating all six checks to `drvPath` | 37 s | 3.64 GiB |
| `nix flake check` | 66 s | 4.64 GiB |
| `nix-fast-build --flake .#checks.x86_64-linux` | 31 s | 2.26 GiB |
| one `nix build` per check, largest (`chungito`), measured on `chungito` | 13 s | 1.71 GiB |
| building all six, warm store | 27 s | negligible |

Cold, there is ~500 MiB to download, mostly the desktop closures of hosts this
machine doesn't run - `ffmpeg-full`, `gerrit`, and whatever `chungito` and
`fw13` drag in.

The shape of that is the whole design: **evaluation is the expensive phase and
it is single-threaded.** The 233 derivations a full check builds are `etc`,
`system-units`, `activate` - config-file assembly, not compilation. Nothing
here needs a big machine; one thing here needs a few gigabytes of RAM for half
a minute.

### What `pizza` has

7.6 GiB of RAM and 8 GiB of swap, 8 cores, 146 G free on `/nix`, and - from
Prometheus over the retention window - `MemAvailable` never below **4.79 GiB**.

So disk and CPU are non-issues, and the entire question is whether a few
gigabytes of evaluation fit in that headroom next to Gerrit's JVM.

### What Gerrit is missing

- **There is no `Verified` label on this instance.** Gerrit only creates it if
  you say yes to a prompt during `gerrit init`, and the nixpkgs module runs
  init non-interactively. It has to be added to `All-Projects`.
- **The Checks tab needs a frontend plugin, not a packaged one.** The tabbed
  CI panel is built into the web UI and hidden until a JavaScript plugin
  registers a provider with `plugin.checks()`
  (`Documentation/pg-plugin-checks-api.html`). That is one `.js` file in the
  site's `plugins/`, which `services.gerrit.plugins` can install, so nothing
  needs building. The old `checks` backend plugin, which stored checkers in
  NoteDb, is a different thing and isn't needed.

### What else was considered

Two of these aren't hypotheticals: I've used Jenkins and Zuul both, and
deployed Zuul myself. I strongly dislike Jenkins and I like Zuul a lot. That
ordering matters more than the feature comparison, so it's written down rather
than left implicit.

- **Jenkins + `gerrit-trigger`** is the canonical answer and it works. It is
  also Jenkins, which I'm not willing to run here, and it puts a second JVM on
  the box whose memory is the binding constraint.
- **Zuul** is the one I'd actually want if this were a real CI system. It isn't
  in nixpkgs, and it wants ZooKeeper, a scheduler and executors, so it's
  overkill for one job on one project today.
- **Buildbot** is in nixpkgs at 4.3.0 with NixOS modules, and its Gerrit
  support is genuinely first-class: `GerritChangeSource` consumes
  `gerrit stream-events` over SSH and `GerritStatusPush` votes back.
- **`buildbot-nix`** evaluates `.#checks` in parallel, one build step per
  attribute, which is exactly this repo's shape - but upstream supports GitHub
  and Gitea only. The Lix fork does speak Gerrit and runs in production for
  them; their own infrastructure guide describes it as janky on auth, buggy,
  and non-discoverable about which change caused a build.

So if this ever outgrows a bespoke runner, the path is: **try Buildbot first**,
because being packaged with a NixOS module is a real head start and the Gerrit
support is there. If I don't get on with it, deploy Zuul despite the extra
work. Buildbot wins the tiebreak on packaging, not on merit.

## Decisions

1. **It runs on `pizza`.** The measurements above say it fits, and always-on
   beats fast for something whose latency budget is "before I get round to
   reviewing it".

   **Rejected: `chungito`.** It has the cores and the store already, and it is
   asleep most of the time. Wake-on-LAN to run a 30-second job is a moving part
   in exchange for nothing - the expensive phase is single-threaded, so
   `chungito`'s advantage over `pizza` is much smaller than its core count
   suggests.

   **Rejected: `slopbox`.** It's an Incus VM on `chungito`
   (`tf/slopbox/slopbox.tf`), so it inherits `chungito`'s availability and none
   of its independence - rejecting `chungito` for sleeping and then picking a
   guest of it would be picking the same machine with extra steps. Its 32 GiB
   and its cores are lent by the host, not its own. And it's where the agent
   runs, so CI there is the arrangement in which "it worked on my machine" and
   "it passed" are the same statement.

1. **The job is one `nix build` per check, not `nix flake check`.** `nix flake
   check` evaluates the whole flake and holds it live, 4.64 GiB. A process per
   check frees each configuration's evaluation before starting the next, so the
   peak is the largest single configuration, 1.71 GiB.

   This is the decision that makes decision 1 true. Against 4.79 GiB of
   worst-case headroom, `nix flake check` leaves about 150 MiB - which is not
   headroom, it's a coin flip - and the loop leaves about 3 GiB. The margin
   also has to absorb every host added to the flake from here on, because
   evaluation cost scales with them.

   We started with `nix-fast-build`, whose 2.26 GiB above was measured on
   slopbox. On pizza it ran eight `nix-eval-jobs` workers, one per core, which
   swapped the whole host into the ground. Limited to the one worker pizza can
   afford, it does nothing this loop doesn't.

1. **The unit is contained, and when it dies it says so in Gerrit.** Two halves
   of one requirement.

   *Contained*, because the failure that matters is not the check failing; it's
   the kernel reclaiming under pressure and the OOM killer choosing the JVM
   whose NoteDb is the point of the whole system. So: `MemoryHigh` below the
   headroom so the job throttles and swaps rather than growing into Gerrit,
   `MemoryMax` above it so a runaway evaluation dies instead of the JVM, `Nice`
   and `IOSchedulingClass=idle` to keep it off Jellyfin's back, and `CPUQuota`
   well under the core count since the job can't use them anyway.
   `OOMPolicy=continue`, so that an evaluation killed at `MemoryMax` fails the
   check rather than taking the runner down with it.

   Contained also means not root. The runner evaluates whatever anyone with
   push access uploads - slopbot included - so it runs as its own system user,
   and a Nix evaluation or sandbox bug costs that account rather than the host.
   Its builds go through the daemon as a result, outside the unit's cgroup, so
   the limits bound evaluation only; that's the expensive phase anyway.

   *Loud*, because a runner that is broken and silent looks exactly like a
   runner that hasn't got to your change yet. The absence of a `Verified` vote
   is safe - it blocks submission - but it is not *informative*, and I'd be
   sitting waiting for a result that is never coming. So an `OnFailure=` unit
   posts a message on whatever change was in flight saying the runner died and
   no result is coming. It needs no detail; "I'm broken, don't wait for me" is
   the entire content. It has to be a separate unit precisely because the
   interesting case is the one where the runner was killed and cannot report
   for itself.

   A check that killed the runner must not simply be retried: if the patch set
   is what killed it, it will again, and while it's the newest change nothing
   older ever gets checked. So on startup the runner votes -1 on the patch set
   the in-flight file names, and a new patch set is what checks it again.

   Short of dying, anything that stops the runner reaching a vote - a failed
   fetch, a vote Gerrit refused - is posted on the change, once per patch set
   per runner lifetime, and then retried quietly by the sweep.

   That is belt-and-braces over the existing failed-unit alerting, which stays
   and is what catches the case where the runner dies with nothing in flight.

1. **It's its own tool, `gerrit-ci`, and the Gerrit client becomes a library.**
   `slop-tools` is about the lifecycle of agentic coding - propose a change,
   answer review, resume a session. Checking that a submission builds is a
   property of the repository and would want to exist if no agent ever touched
   it. Putting it in `slop-tools` would be filing it by which code it can reuse
   rather than by what it is.

   So `packages/slop-tools` becomes `packages/go-tools`, one Go module that
   both `slop-tools` and `gerrit-ci` are built from as separate packages, and
   `internal/gerrit` becomes an ordinary importable `gerrit` package. It's
   already the right shape for this - `StreamEvents`, `Query`, `Review`, and a
   `ReviewInput` that already carries `Labels map[string]int`, so casting
   `Verified±1` is one field on a type that exists.

   The reconnect-with-backoff and sweep logic in `slop-handler` is the other
   thing worth sharing; whether that moves into the library too or gets written
   again in fifty lines is a decision better made with both callers in front of
   me than now.

   **Rejected: Buildbot, for now.** See the survey above for where it sits;
   the point here is that nothing in this design forecloses it. A bespoke
   runner that votes on a label is exactly what Buildbot's `GerritStatusPush`
   would do, so replacing it later is a swap, not a migration.

   **Rejected: the `hooks` plugin.** It's already enabled, and a
   `patchset-created` script is the smallest possible thing by some margin. But
   the hook runs synchronously inside Gerrit's process tree, with Gerrit's
   resource limits and no ability to defer, batch or retry - and a hook that
   takes 30 seconds and 2 GiB is a hook that makes pushing feel broken.

1. **The full log is a file, served as plain text through the IAP.** Each run
   writes its output to `logs/CCCC-P.txt` in the runner's state directory, and
   the review message carries a one-line verdict, the last few lines, and a URL.

   The runner serves that directory itself, behind an ordinary
   `bjackman.iap.services` entry with `forwardAuth` and
   `allowedUsers = [ "brendan" ]`. Next to each log it writes
   `logs/CCCC-P.json`, a record of the run, and it serves
   `/api/checks/<change>`: that change's runs, queued, running and finished,
   already in the shape of the Checks API. A `gerrit-ci.js` frontend plugin
   fetches that and hands it to the Checks tab. The records are for display
   only; whether a patch set needs checking is still the vote's job.

   The plugin fetches cross-origin with the IAP session cookie, which works
   because both hosts are under `home.yawn.io`. When that session expires, the
   redirect to the login page fails CORS and the tab shows an error until the
   runner's URL is visited again.

   Logs are pruned by age rather than kept forever; a fortnight is longer than
   any change stays open in practice.

   This is what the first draft of this design got wrong. It proposed the tail
   of the output in the review message and called the missing log an acceptable
   trade - but "the last twenty lines didn't explain it, go run it locally"
   describes exactly the failure that most needs CI, and a plain text file over
   HTTP costs almost nothing.

1. **The runner votes as `ci-bot`.** A distinct account, so that "the agent
   wrote this" and "CI passed this" are visibly different identities in a UI
   whose whole job is telling me who did what.

   It costs little: the account only ever speaks SSH, so it needs a key and no
   Authelia password. It does need creating the way every other account here is
   created - by logging in as it against loopback with the identity headers set,
   per `gerrit.md` decision 6 - because an account made through the API gets a
   `username:` external ID and never a `gerrit:` one, and that mismatch is
   permanent. `gerrit-bootstrap` already does exactly this dance for `slopbot`;
   `ci-bot` is another entry in `users.json` marked `serviceAccount` and a
   second pass through the same code.

   It belongs in `Service Users` for the same reason `slopbot` does: nothing
   should be adding a bot to my attention set.

1. **Project configuration is a file in this repo, pushed to
   `refs/meta/config`.** The `Verified` label, its submit requirement and the
   `label-Verified` grant to `ci-bot` are all `project.config` stanzas, and
   `project.config` is a file on a git ref. Expressing them as REST calls means
   translating a file format into API calls so that a bootstrap script can
   translate them back.

   This reverses `gerrit.md` decision 12, which rejected the git route on the
   grounds that the REST API edits the same thing without fetching, rewriting
   and pushing a config file, and that the only non-default rule was one line.
   That reasoning was sound for one line. It doesn't survive a label definition,
   which is a dozen lines of a format designed to be a file - and the balance
   tips further with each rule added.

   So: `gerrit_config/<project>/project.config` in this repo for each project
   we create, and `gerrit-bootstrap` fetches `refs/meta/config`, replaces the
   file with the in-repo version, commits and pushes if anything changed. Never
   `All-Projects`: it holds every default, and replacing its config wholesale
   would drop the lot. The existing `Push` grant for
   `Administrators` moves there too, which is most of what the REST reconciler
   currently does.

   **What can't move** stays REST, and the split is clean rather than arbitrary:
   accounts, SSH keys, registered addresses and group membership are not project
   configuration. They live in NoteDb under `All-Users`, and while that is also
   git underneath, editing it by hand is not a supported interface.

   **The snag is the `groups` file.** A rule in `project.config` names a group,
   and the sibling `groups` file maps that name to a UUID. `Administrators` and
   `Service Users` get random UUIDs at `gerrit init`, so the file can't be a
   static checked-in artefact. Bootstrap generates it: one REST call per group
   named by the config, then write the mapping alongside the config in the same
   commit. That keeps the reviewable part - the rules - in the repo and the
   instance-specific part generated, which is the right seam.

1. **`stream-events` for latency, a sweep for correctness - and no debounce.**
   The same split as `slop-handler`, the agent's review handler, and for the
   same reason: a long-lived SSH connection can drop and a dropped stream is
   invisible.

   Unlike `slop-handler`, there is nothing to debounce. It batches by topic
   because six comments across a series are one conversation; a patch set is a
   patch set, and each one is independently either good or not. The sweep query
   is open changes whose current patch set carries no `Verified` vote, which is
   self-correcting: anything missed by a dropped stream is picked up, and
   anything already voted on is skipped without needing state on disk.

   That statelessness is worth having explicitly. `slop-handler` needs a
   handled-comments file and the adoption rule that goes with it; the runner's
   "has this been done" lives in Gerrit, as the vote itself.

1. **One project, one job, votes -1 or +1.** `boxen` only - `lkml-tags` is a
   place to push tags and has nothing to check. `Verified-1` on failure rather
   than -2: it blocks submission via the submit requirement, and an
   Administrator's `Verified+1` overrides it for the times the check is red for
   reasons that have nothing to do with the change.

1. **The runner submits what's ready, and only onto the commit it checked.**
   Ready means `is:submittable` - my `Code-Review+2` and `Verified+1`, so the
   +2 is what says "ship it when it's green" - and neither WIP nor private,
   which is the way to hold one back. A change in a stack only goes when every
   change beneath it is ready too, and the bottom one's parent is the tip of
   its branch. Gerrit already refuses to submit a change over an unsubmittable
   ancestor; the tip condition is the runner's own. The project rebases if
   necessary on submit, so a green stack on a stale base would otherwise land
   as a tree nothing ever built, with nobody looking. A stale stack
   sits until it's rebased, which makes new patch sets and so a fresh check.

   It's a pass over the open changes at the start of each sweep and after each
   vote, submitting the top of one ready stack at a time - Gerrit takes the
   rest along - and recomputing in between, since each submit moves the tip.
   `comment-added` and `change-merged` wake a sweep as well as
   `patchset-created`, so a +2 on something already green goes straight in.
   `ci-bot`'s group holds `submit` on `refs/heads/*` for it.

## Design

### `nixos_modules/gerrit-ci.nix`

A `gerrit-ci` unit on `pizza`, alongside the Gerrit module rather than inside
it, plus an IAP service for the logs:

```nix
bjackman.ports.gerrit-ci-logs = { };
bjackman.iap.services.gerrit-ci-logs = {
  port = config.bjackman.ports.gerrit-ci-logs.port;
  forwardAuth = true;
  allowedUsers = [ "brendan" ];
};

systemd.services.gerrit-ci = {
  after = [ "gerrit.service" "network-online.target" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  onFailure = [ "gerrit-ci-failed.service" ];
  serviceConfig = {
    ExecStart = "${pkgs.bjackman.gerrit-ci}/bin/gerrit-ci";
    User = "gerrit-ci";
    Restart = "always";
    RestartSec = 30;
    StateDirectory = "gerrit-ci";
    MemoryHigh = "3G";
    MemoryMax = "4G";
    MemorySwapMax = "2G";
    OOMPolicy = "continue";
    CPUQuota = "400%";
    Nice = 10;
    IOSchedulingClass = "idle";
  };
};
```

The state directory holds one clone of `boxen`, fetched into rather than
re-cloned per run, and `logs/`, which the runner serves.
`gerrit-ci-failed.service` is decision 3's loud half: it reads the in-flight
patch set from a file the runner writes before it starts work, and posts "the
runner died" on it.

### The runner

Per patch set:

1. `git fetch origin refs/changes/NN/CCCC/P`, check it out detached.
1. `nix build --no-link .#checks.x86_64-linux.<name>` for each check in turn,
   output to `logs/CCCC-P.txt`.
1. `gerrit review CCCC,P --json` with `{"labels": {"Verified": ±1},
   "message": ...}`, the message being the verdict, the last few lines on
   failure, and the log URL.

Serialised - one build at a time, newest patch set wins if several are pending.
Concurrency is what would break decision 3's memory arithmetic, and there is no
throughput problem to solve.

### The label

`gerrit_config/boxen/project.config`, pushed to `refs/meta/config` by
bootstrap per decision 7:

```
[label "Verified"]
    function = NoBlock
    value = -1 Fails
    value =  0 No score
    value = +1 Verified
```

with the blocking behaviour expressed as a submit requirement rather than the
legacy `MaxWithBlock` function, since that's the mechanism 3.13 actually wants,
and the `label-Verified` grant to `ci-bot` in the same file. The requirement's
`overrideIf` is what makes the manual override work: `submittableIf` rejects
any `Verified-1`, so without it an Administrator's +1 next to `ci-bot`'s -1
would change nothing.

## Gotchas and open questions

- **Evaluation cost grows with the flake.** 2.26 GiB is today's number, for six
  systems. Every host added to `nixosConfigurations` pushes it up, against a
  headroom that doesn't grow. The `MemoryMax` failure in decision 3 is what
  turns that from a silent risk into an alert, but the eventual answer is
  building somewhere else.
- **Red for reasons that aren't the change.** Fixing
  `caddy-src-with-plugins` to write this made the point: the flake was already
  failing on `master` because nixpkgs moved Caddy and the pinned FOD hash went
  stale. A blocking presubmit turns that class of drift from "noticed at deploy
  time" into "every change is blocked until someone bumps a hash". That's
  mostly an improvement, and it does mean the manual `Verified` override in
  decision 9 is load-bearing rather than decorative.
- **Pushing `refs/meta/config` can lock you out.** It's the ref that says who
  may push, so a bad config is a bad config that also refuses the fix. The
  admin key is on `pizza` and `gerrit-bootstrap` runs as root there, which is
  the escape hatch, but this deserves care that a REST call didn't need - the
  push should be a no-op when nothing changed, so that a broken generation
  isn't rewritten on every boot.
- **`nixpkgs` bumps are the expensive case**, not changes. A flake input update
  invalidates every closure and turns a 30-second job into a large download.
  Worth watching what that does to the box before assuming the numbers above
  describe the worst case.
- **The store grows.** Every patch set's closures stay until GC, including
  closures for hosts `pizza` doesn't run. 146 G is a lot of room, but this is
  the thing that will quietly eat it, and `nix.gc` on `pizza` should be checked
  against that rather than assumed adequate.
- **A patch set is checked as uploaded, not rebased onto `master`.** A change
  based on a stale `master` can be green and still break it once submitted.
  Rebasing before submitting makes a new patch set, which is checked afresh,
  so it's a matter of doing that when `master` has moved. Auto-submit only
  takes stacks that sit on the tip, so this is down to submitting by hand. The
  flip side is that a ready stack on a stale base waits silently: nothing tells
  anyone it needs a rebase.
- **The agent doesn't hear about a red check.** `slop-handler` wakes on my
  comments, not on `ci-bot`'s, so a `Verified-1` on a slopbot change waits for
  me to notice it. Feeding it through is the obvious next step.
- **This checks that it builds, not that it deploys.** `toplevel` building has
  never been the same as the machine coming back up. Unchanged from today,
  where I check the same thing by hand, but worth not mistaking the green tick
  for more than it is.
