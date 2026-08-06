# Automated flake updates

**Status: not implemented.** This is a design only. Nothing described here exists in the
repo yet, apart from the observations in "What was verified", which were checked against
the tree as of 2026-08-06 (nixpkgs `8c3cede7`, Nix 2.34.8).

## Goal

Run `nix flake update` on a schedule. In the common case where nothing but `flake.lock`
needs to change, this should cost **zero** LLM tokens. When something does break, escalate
to Opus with enough context that it can fix it in one bounded session.

## Shape

The deterministic work is driven by a shell script. No model is in the happy path at all —
not even a cheap one — because deciding to run `nix flake update && nix flake check`
requires no judgement.

```
update-flake.sh
  git checkout -B auto/flake-update origin/master
  nix flake update            # per input policy below
  nix flake check             # gate, see "Warnings"
  ok  → commit "nix flake update", push branch, notify, exit 0
  bad → isolate, then escalate
```

### Isolation before escalation

A bulk update touches ~18 inputs, so a bulk failure says nothing about the cause.
Attributing it is mechanical, and machine time is far cheaper here than Opus tokens. On
failure, throw the bulk lock away and redo it greedily:

```
for input in $inputs:
    nix flake update $input      # onto the accumulated-good lock
    if nix flake check: keep it
    else: revert this input, record (input, oldRev, newRev, failing drv, log tail)
```

Two payoffs. It produces a **partial lock that actually builds** — mergeable today, no LLM
involved — and it hands the escalation a precise statement ("`nixos-raspberrypi` a1b2→c3d4
breaks `norte-system-toplevel`, here is the log tail and the upstream commit range")
instead of a five-figure line count of build output. Roughly 18 sequential
`nix flake check` runs is slow but almost all cache hits after the first.

### Escalation contract

Invoke Opus headless with a tight brief.

- **Input:** the isolation report plus the repo at the partially-updated branch.
- **May:** read upstream release notes and the commit range, edit Nix code to adapt,
  re-run `nix flake check`, and either land the input or leave it pinned **with a written
  reason**. The pinning authority matters — see the caveat under "Warnings", where the
  correct fix is sometimes "wait for upstream", and no amount of local editing helps.
- **May not:** deploy anything, touch `master`, force-push.
- **Output:** commits on the branch plus a short report of what it changed and what it gave
  up on.
- **Bounded:** hard cap on turns and wall-clock. On exhaustion it reports what it learned
  rather than thrashing.

### Repeat-failure suppression

This is the actual cost control. Without it, an upstream that stays broken for three weeks
means Opus re-solving the same problem nightly.

Keep a state file keyed by `(input, newRev, error fingerprint)`. A matching fingerprint
skips the LLM entirely and re-reports "still blocked on X, see branch Y". Only a *new*
fingerprint buys a session.

Steady state is therefore: most nights zero tokens, occasionally one bounded Opus session.

### Input policy

The inputs do not all want the same cadence.

- **Auto:** nixpkgs, home-manager, disko, agenix, nixos-hardware, treefmt-nix,
  nix-index-database, deploy-rs, impermanence, and similar upstream flakes.
- **Excluded, or a separate job:** `tvheadend` (`flake = false`, tracks master, so it
  churns constantly and forces a full source rebuild every run) and the personal repos on
  feature branches — `jellarr@network-settings`, `sashiko@nix`, `limmat`. For those,
  "update" is a decision, not something a cron should make.

### Delivery

Never touch `master`. Push `auto/flake-update` and notify by email, which fits the existing
Alertmanager habit. Merging stays a manual `git merge --ff-only` after a glance. Letting
the trivially-green case land itself is a one-line policy change later if wanted.

## Warnings

Eval warnings fail nothing by default, so a naive gate would happily green-light a config
quietly accumulating deprecations until one of them becomes a hard error.

The fix is a flag on the existing command, in `limmat.toml` and in the update script:

```toml
[[tests]]
name = "flake-check"
cache = "by_tree"
command = "nix flake check --abort-on-warn"
```

`NIX_CONFIG="abort-on-warn = true"` works equally well if it is preferable to set it once
in the script's environment so nested invocations inherit it.

This needs no `flake.nix` change. A new deprecation simply becomes a red check, and the
isolation and escalation machinery above handles it identically to a build failure — the
greedy loop attributes the warning to a specific input bump for free.

An earlier draft of this design split warnings into two classes needing two mechanisms
(structured `config.warnings` versus stderr traces) and proposed a `runCommand` check over
`config.warnings`, with stderr scraping and set-diffing against a baseline for the rest.
That was all unnecessary — see below.

### Caveats

- **The flag is global, so it escalates warnings that cannot be fixed locally.** A nixpkgs
  bump can introduce a trace from inside a package the config merely references. The only
  responses are to pin the input and wait. This is the main argument for the hard gate
  being paired with explicit pinning authority in the escalation contract.
- **First warning only.** Fine for gating, useless as an inventory. The escalation gets a
  stack trace instead (`--show-trace` for the full one), which is more useful than the
  message alone because it names the triggering file. Producing a complete list means
  re-running without the flag and scraping stderr, which is an escalation-time nicety, not
  part of the gate.
- **Only the eval path actually forced is covered.** `nix flake check` covers `checks` and
  `devShells`, which is what matters.

## What was verified

- **`config.warnings` and `lib.warn` are the same mechanism.**
  `showWarnings = warnings: res: foldr warn res warnings` (`lib/trivial.nix:1051`), and
  `lib.warn` resolves to `builtins.warn` on Nix ≥ 2.23 (`lib/trivial.nix:867`). NixOS wires
  it in at `nixos/modules/system/activation/top-level.nix:78`:

  ```nix
  baseSystemAssertWarn = lib.asserts.checkAssertWarn config.assertions config.warnings baseSystem;
  ```

  So evaluating `system.build.toplevel` routes renamed-option warnings through
  `builtins.warn`, and one flag catches every class of warning. The same function `throw`s
  on failed assertions, so those already hard-fail.

- **The repo is already clean under the flag.** Every config evaluated with
  `--abort-on-warn` at the time of writing: `pizza`, `chungito`, `fw13`, `slopbox`,
  `brendan`, `niamh`, `jackmanb@bj`, `jackmanb@jackmanb01`. No cleanup is needed to adopt
  the gate.

- **The eval cache does not suppress warnings.** Checked on a clean committed tree with a
  warm cache; the warning printed on every run. `--no-eval-cache` is unnecessary. The lock
  file changes each run anyway, so the cache key differs regardless.

- **`--abort-on-warn` works through `nix flake check`**, not just `nix eval`, and via
  `NIX_CONFIG`.

## Out of scope

**aarch64.** `checks."${system}"` filters on `hostPlatform.system == x86_64-linux`
(`flake.nix:382-386`), so `norte` and `sandy` are not covered by `nix flake check` on an
x86 host. A green lock from this job therefore says nothing about whether norte still
builds, and norte is the fragile one — `nixos-raspberrypi` deliberately does not follow
`nixpkgs`. Deliberately deferred; the report should state that aarch64 is unverified rather
than implying full coverage.

If picked up later, the options are, roughly in order of preference: broaden `checks` and
run the job with an aarch64 remote builder; cross-build using the existing `pkgsCross`
machinery (`flake.nix:134`); or `binfmt` emulation on pizza.
