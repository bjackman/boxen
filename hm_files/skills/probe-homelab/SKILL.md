---
name: probe-homelab
description: Look at the live state of Brendan's homelab hosts (pizza, norte) from slopbox - journals, unit state, disk and ZFS health, what was deployed when. Use when investigating something in prod rather than in the config, when an alert or a bug report needs evidence from a running machine, or when you would otherwise want to SSH into a homelab host.
---

# Probing the homelab

Agents on slopbox have no shell on the homelab hosts. What they have is
`slop-probe`, which runs one of a fixed set of read-only commands declared in
`nixos_modules/slop-probe.nix` and deployed to the host. Everything below is
safe to run unattended; none of it can change anything.

```
slop-probe <host> <probe> [--option=value | --option value | --switch]...
slop-probe <host> list      # what this host offers, with each option's pattern
slop-probe hosts            # what hosts there are
```

The set is per-host, not global: norte declares `zpool-status` and `zfs-list`,
pizza doesn't. `list` is the authoritative answer for a given host.

Output goes to stdout, so **filter it in the pipeline** rather than asking for
everything and reading it all:

```bash
slop-probe pizza journal --unit forgejo.service --since=-2h | grep -i error | tail -40
slop-probe norte journal --priority 3 --since=-1d | wc -l
```

Values that begin with `-` need the joined form (`--since=-1h`), otherwise both
spellings work.

## Reading a failure

1. `slop-probe <host> units --failed` - anything systemd is unhappy about.
1. `slop-probe <host> unit-status --unit <unit>` - state, recent lines, process
   tree. Note this exits non-zero for an inactive unit; that's systemctl
   talking, not an error.
1. `slop-probe <host> journal --unit <unit> --since=-1h` - the detail, narrowed.
1. `slop-probe <host> journal --dmesg --priority 3` - if it smells like
   hardware or the kernel.

## Was it a deploy?

```bash
slop-probe pizza generations                 # profile links with timestamps
slop-probe pizza current-system              # store path running now
slop-probe pizza closure-diff --from=<old> --to=<new>
```

Line the timestamp of the generation up against when the symptom started. The
`from` path is the target of an older `system-N-link` from `generations`.

## Metrics are a separate, older channel

Prometheus on pizza is reachable directly and needs no auth, so for anything
with a time series, query it instead - and see the `investigate-alert` skill:

```bash
curl -s 'http://pizza:9090/api/v1/query?query=<url-encoded-promql>' | jq .
```

Retention is 15 days. Beyond that the journal is what's left.

## Exit statuses

The probe's own, except **111** (the host refused the request - unknown probe,
unknown option, or a value the option's pattern doesn't allow), **112** (the
host stopped the probe for taking too long or producing too much - narrow the
query and retry), **255** (the connection failed) and **1** (the client
rejected the command line before connecting, e.g. an unknown host name).

## When the probe you want doesn't exist

That is the expected way to hit a wall, and the answer is never to look for
another way onto the host. The probes live in `nixos_modules/slop-probe.nix` in
the `boxen` repo. If you're working in a boxen worktree, add it there and
propose it with `slop-pr`; if you aren't, say which probe you need and leave
starting the change to Brendan. A probe is: a `command`, the `args` it always gets, and a
`params` entry per option whose `regexpPattern` is tight enough that the option
can't become a different command. Keep it read-only. Brendan deploys it and the
capability is there for good.
