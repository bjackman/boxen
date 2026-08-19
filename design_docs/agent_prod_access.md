# Agent access to prod

**Status: proposal, nothing here is implemented.** Sibling to
[`agent_prs.md`](agent_prs.md): that document gets a change *out* of slopbox,
this one gets evidence *in*.

## Goals

1. An agent on slopbox can investigate the live homelab — metrics and journals
   first — before it proposes a change, without me being in the loop.
1. It cannot change the homelab. Config changes go through a pull request, which
   is already the rule in `CLAUDE.md`; this makes it a mechanism instead of a
   prompt.
1. Growing what the agent can see is itself a pull request, so the review cost
   is per *capability*, once, rather than per *invocation*, forever.

Non-goal: defending against a hostile agent. slopbox is a machine I own, on my
tailnet, and Prometheus is already unauthenticated to anything on that tailnet.
The thing being contained is a confused agent with a plausible-sounding reason
to run `systemctl restart`, not an attacker. That framing is what keeps this
design small; if the threat model changes, most of the decisions below change
with it.

## Background

### What exists

- `nixos_modules/prometheus/` — Prometheus + Alertmanager on `pizza`, listening
  on `0.0.0.0` with the port opened only on `tailscale0`. Perses on top for
  dashboards.
- `nixos_modules/slopbox.nix` — the agent VM. Already on the tailnet
  (`100.92.183.118`), `services.tailscale.enable` defaulted true via
  `ssh-server.nix`.
- `.agents/skills/investigate-alert/` — already tells the agent to hit
  `http://pizza:9090/api/v1/...` with `curl` and `jq`, and to `ssh pizza` for
  the journal.
- `hm_modules/agent-host-context.nix` — the always-on discovery channel for
  anything an agent is supposed to know about this host.
- `packages/slop-tools` — Go, already home to `slop-pr` and `slop-handler`.

### What actually works from slopbox today

Verified by running it there:

- `curl http://pizza:9090/api/v1/status/buildinfo` → 200. **The metrics half of
  goal 1 already works** and needs no new code.
- TCP 22 is open on `pizza` and `norte` from slopbox, but `ssh pizza` fails —
  there is no key for `brendan` on slopbox, only the `slopbot` Forgejo key. So
  the agent has *no* shell on any homelab host, and the `investigate-alert`
  skill's step 3 is a dead letter when run unattended.
- `pizza:19531` closed — no journal gateway anywhere.
- Prometheus retention is the 15d default, so "what happened three weeks ago" is
  not answerable from metrics.

So the gap is exactly journals plus a general command channel, as suspected.

## The interface question: a command, or a harness integration?

Both a CLI and an MCP server would run *as the agent*, with the agent's
credentials, on slopbox. Neither can constrain what the agent does — the agent
runs with `bypassPermissions` and a shell, so anything the harness "denies" it
can do by other means. **The permission model therefore has to live on the
target host, and once it does, the interface layer is a pure ergonomics
choice.** That removes the usual reason to reach for MCP.

On ergonomics the CLI wins on the thing that matters most here:

- **Output volume is unpredictable, and only a pipeline can fix it after the
  fact.**

  ```
  slop-probe pizza journal --unit forgejo --since -1h | grep -i tls | tail -40
  ```

  That costs the agent 40 lines. The same query as an MCP tool call puts the
  entire hour of logs in the context window, and the model has to guess the
  right filter *before* it sees the data. Debugging is precisely the workload
  where that guess is wrong. This is close to decisive on its own.

- **Discovery cost scales the wrong way for MCP.** Tool schemas sit in context
  permanently and grow with the probe list, which decision 7 is designed to make
  grow. A skill plus `slop-probe <host> list` costs nothing until used.

- **I can run it.** Same binary, same arguments, from my shell, to see exactly
  what the agent saw. And it keeps working from a cron job, a shell script, or a
  different agent harness.

- **One less moving part.** A binary in `environment.systemPackages` is how
  `slop` and `slop-tools` already ship. An MCP server is a per-session process,
  a handshake, and a `settings.json` entry outside Nix.

MCP would be the right answer if the harness were the enforcement point (it
isn't), if access needed an interactive OAuth dance (it doesn't), or if we
wanted the agent to have *no* shell (we don't — the point of slopbox is that it
does). Worth revisiting only if an agent ever runs somewhere shell-less.

**Decision: a CLI, discovered through `agentHostContext` and a skill.**

## Decisions

1. **Metrics need no new mechanism.** Prometheus stays as it is: reachable,
   unauthenticated, tailnet-only. The existing skill already documents the API.
   The only change worth considering is retention (open question 3).

1. **Everything else goes through `slop-probe <host> <probe> [options]`,
   transported over SSH to a forced command.** slopbox gets a dedicated key;
   each homelab host gets a `slopbot` user whose `authorized_keys` entry is
   `restrict,command="…/slop-probe-server"`. The client sends a JSON request on
   stdin; the server ignores `SSH_ORIGINAL_COMMAND` entirely, so no string the
   agent composes is ever parsed as a command anywhere.

   SSH rather than a small HTTP daemon (the obvious alternative) because port 22
   is already open to the tailnet on both hosts: no new listener, no firewall
   change, no new authentication scheme, and revocation is deleting a line from
   `authorized_keys`.

1. **Capabilities are named probes declared in Nix, with typed options — never
   free-form argv.** A probe is a name, a description, a store path to exec, and
   a set of options each with a validation pattern. The server looks the probe
   up in a manifest generated by Nix, validates each option, and `exec`s the
   store path with the options as argv. There is no shell on the target side of
   the connection.

   ```nix
   bjackman.slopProbe.probes.journal = {
     description = "Read the systemd journal";
     command = "${config.systemd.package}/bin/journalctl";
     args = [ "--no-pager" ];
     params = {
       unit = { flag = "--unit"; regexpPattern = "[A-Za-z0-9@:_.-]+"; };
       since = { flag = "--since"; regexpPattern = "[-+A-Za-z0-9 :,.]+"; };
       priority = { flag = "--priority"; regexpPattern = "[0-7]"; };
       grep = { flag = "--grep"; regexpPattern = ".{1,200}"; };
       reverse.flag = "--reverse";
     };
   };
   ```

   Patterns are anchored at both ends by the server, so they say what a value
   may be rather than what it may contain.

   The alternative — a sudoers-style allowlist of command prefixes — was
   rejected. `journalctl` alone has `--rotate`, `--vacuum-size` and `--flush`;
   deciding which *flags* are safe by pattern-matching free argv is a game you
   lose eventually. Naming the flags a probe accepts makes the safe set explicit
   and reviewable in a diff.

1. **The `slopbot` target user gets `systemd-journal` and nothing else.** No
   sudo in v1. `journalctl`, `systemctl status/show/list-units`, `zpool status`,
   `df` and `nix store diff-closures` all work unprivileged. A probe that
   genuinely needs root gets its own `security.sudo.extraRules` entry naming the
   exact store path — one reviewed line per privileged capability, not a blanket
   grant. `smartctl` is the likely first candidate and doesn't need one, since
   the smartctl exporter already feeds Prometheus.

1. **Output size and wall-clock are capped server-side** (1 MiB, 60s, both
   overridable per probe). Truncation is reported explicitly so the agent knows
   to narrow the query rather than silently reasoning about half a log. This
   protects the host and, just as importantly, the agent's context window.

1. **Every invocation is logged on the target**, with a distinct syslog
   identifier, so `journalctl -t slop-probe` on pizza is a complete audit trail
   of what the agent looked at. The agent can read that log through the journal
   probe; per the threat model that's fine.

1. **A new capability is a pull request.** When the agent hits a wall it writes
   the probe definition, sends it through `slop-pr`, and I deploy it. This is
   the reason the permission model is declarative Nix rather than a runtime
   allowlist: the capability set is reviewed the same way and in the same place
   as everything else, and it ratchets — each investigation that hits a wall
   makes the next one cheaper.

1. **Scope is `homelab.nodes` — pizza and norte.** Not chungito: it's my
   workstation and it's slopbox's own hypervisor, so a probe into it is a
   containment hole rather than a monitoring feature. Not sandy, until there's a
   reason.

1. **Discovery is `agentHostContext` plus a skill.** A paragraph in
   `hm_modules/slopbox.nix` saying the command exists and what it's for; a
   `probe-homelab` skill with recipes; `slop-probe <host> list` for the
   authoritative, always-current probe list from the target's own manifest. The
   existing `investigate-alert` skill's step 3 gets rewritten to use it instead
   of `ssh`.

### Why journals are a probe rather than `systemd-journal-gatewayd`

`services.journald.gateway.enable` exists and would be a two-line change per
host, unauthenticated on the tailnet exactly like Prometheus. Rejected because
its HTTP API filters by field match, boot and cursor byte-range — but not by
time, and it has no `--grep`. "Errors from forgejo.service in the last hour"
becomes "fetch the last N thousand entries and filter client-side", which is the
over-fetch that decision 5 and the whole CLI argument exist to avoid. Running
real `journalctl` behind the probe mechanism costs one probe definition and
gives `--since`, `--until`, `--priority`, `--grep` and `-o cat`.

It also would have been a second, differently-shaped access path to maintain,
when the probe mechanism has to exist anyway.

## Implementation sketch

- `packages/slop-tools/cmd/slop-probe` — client. Takes a host, a probe and its
  options, streams stdout and stderr through, propagates exit status.
- `packages/slop-tools/cmd/slop-probe-server` — forced command. Reads the
  manifest path from its own argv, the request from stdin, validates, execs.
- `nixos_modules/slop-probe.nix` — the `bjackman.slopProbe` options, the default
  probe set, the `slopbot` user, `authorized_keys`, and the manifest written
  with `pkgs.writers.writeJSON` (same pattern as the Prometheus rules).
  Imported by `pizza` and `norte`.
- `secrets/slopbot-probe-ssh-privkey.age` — a key of its own rather than reusing
  `slopbot-ssh-privkey`. Different capability, independently revocable, and the
  Forgejo key's blast radius shouldn't grow.

Starter probe set: `list`, `journal`, `unit-status`, `unit-show`,
`units` (`list-units`, with `--failed`), `timers`, `disk` (`df`, `zpool status`,
`zfs list`), `processes`, `generations` (`/nix/var/nix/profiles/system-*` with
timestamps) and `closure-diff` (`nix store diff-closures` between two
generations). The last two are the ones that answer "what changed just before
this broke", which metrics can't.

## Open questions

1. **Is a free-form tier needed?** v1 has none: if a probe doesn't exist, the
   agent is blocked and has to ask or send a PR. That's deliberate, but if it
   turns out to block constantly, the fallback is a `shell` probe gated behind
   an out-of-band approval rather than loosening the typed ones.
1. **Journals leak.** Authelia, Samba and Postgres logs contain material I
   wouldn't paste into a prompt. The agent is already trusted with the contents
   of `secrets/` decrypted on slopbox, so this is probably consistent, but it's
   worth deciding rather than defaulting into.
1. **15d retention** makes any "this has been degrading for a month" question
   unanswerable. Cheap to raise on pizza; is there disk?
1. **Alertmanager** is deliberately absent above — the useful part of its API
   (silences) is a write. Read-only `/api/v2/alerts` is already covered by
   Prometheus's own `/api/v1/alerts`.
1. **Does the agent need to reach IAP-fronted service APIs** (Forgejo beyond
   what `slop-tools` does, Jellyfin, the \*arrs) to investigate them, or is
   metrics-plus-journals enough? Deferred until something actually needs it.
