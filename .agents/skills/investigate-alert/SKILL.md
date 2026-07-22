---
name: investigate-alert
description: Investigate a firing alert in Brendan's homelab (Prometheus/Alertmanager on pizza). Use when asked to look into a homelab alert, a "ResticBackupStale"/"HostOutOfDiskSpace"/"ZfsPoolUnhealthy"-style alert, an alert email from the monitoring stack, or "what's firing". Establishes the entry point, then follows a per-alert runbook if one exists.
---

# Investigating a homelab alert

The homelab runs Prometheus + Alertmanager on **pizza**, configured in
`nixos_modules/prometheus/`. Both are exposed on Tailscale, so from any
Tailscale-connected host you can hit them without auth. Alertmanager only emails
Gmail; the API below is the fast path.

Follow this workflow. It is **read-only** — gather evidence and report. Do not
deploy config or mutate hosts (see the repo's `CLAUDE.md`); if a fix needs a
config change, propose it and let Brendan deploy.

## 1. List what's firing

```bash
curl -s http://pizza:9090/api/v1/alerts \
  | jq -r '.data.alerts[] | select(.state=="firing")
           | "\(.labels.alertname) | \(.labels.severity) | \(.labels.instance) | since \(.activeAt)"'
```

Prefer the `curl`/`jq` already on `PATH` over `nix run nixpkgs#curl` (the latter
can be slow on first fetch). Run arbitrary PromQL with:

```bash
curl -s 'http://pizza:9090/api/v1/query?query=<url-encoded-promql>' | jq .
```

If the user was vague about which alert, this list disambiguates. If nothing is
firing, say so.

## 2. Follow the per-alert runbook, if one exists

For each firing alert, look for a runbook at
`references/<alertname-kebab-cased>.md` in this skill directory (e.g.
`ResticBackupStale` -> `references/restic-backup-stale.md`). If present, follow
it — these encode the known failure modes and the exact diagnostic commands, and
they double as human-readable docs.

If no runbook exists, investigate generically (step 3), and when you reach a
conclusion, **write a new `references/<alertname>.md`** capturing what the alert
means, the likely causes, and the commands that diagnosed it, so the next
investigation is faster. Keep it concise; humans are a secondary audience.

## 3. Generic investigation (no runbook yet)

1. Read the rule definition in `nixos_modules/prometheus/rules.nix` — the `expr`,
   `for`, and `description` tell you exactly what tripped and the threshold.
1. Evaluate the `expr` (and its sub-parts) as PromQL against pizza to see the
   current value and which series are involved.
1. Identify the affected host/instance from `$labels.instance`. Homelab nodes
   are reachable over Tailscale/SSH by hostname (`ssh pizza`, `ssh norte`, ...);
   read-only info-gathering over SSH is fine per `CLAUDE.md`.
1. Distinguish a **monitoring-stack fault** (exporter down, scrape failing) from
   a **real condition** on the host. Check the relevant exporter is up and its
   other metrics look fresh before trusting or blaming a single series.
1. Correlate: recent deploys (`git log`), the host's journal for the failing
   unit, Tailscale "last seen" for the instance, related alerts.

## 4. Report

State the alert, the root cause, whether it's server-side or client/host-side,
and the concrete next action. Note whether it will self-clear or needs
intervention. If a durable architectural fact came out of this that isn't
obvious from the code, propose an update to the documentation or skill.
