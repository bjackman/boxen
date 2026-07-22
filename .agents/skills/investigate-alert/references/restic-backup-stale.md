# ResticBackupStale

**Rule:** `nixos_modules/prometheus/rules.nix`, group `Restic`. Fires when a
repo's newest snapshot is older than 2 weeks
(`time() - max by (instance) (restic_backup_timestamp) > 14d`), `for: 1h`,
severity `warning`.

## What the instance label means

`instance` is `<host>_<repo>`, e.g. `norte_romy`. norte is a **backup target**,
not the thing being backed up: it runs an SFTP server, and family members
(`romy`, `niamh`, see `nixos_modules/users.json`) push restic backups **from
their own machines** into per-user chroots at
`/mnt/nas/sftp-chroots/<user>/uploads/restic-repo`. norte runs one
`restic-exporter` per repo (`nixos_modules/norte/restic-exporter.nix`) that
Prometheus scrapes.

## Most likely cause

**The client stopped pushing** — the person's laptop is off/away for a while, or
their local backup schedule broke. This is *not* a norte/pizza fault. Tells:

- `restic_check_success` for the instance is still `1` (repo is intact).
- The exporter is up and other repos on the same host are fresh.
- The client's Tailscale entry shows it "last seen" days ago.

A genuine server-side fault would instead show a failing check, a down exporter,
or a full/offline ZFS pool (which would trip its own alerts too).

## Diagnose

Confirm current staleness across all repos:

```bash
curl -s 'http://pizza:9090/api/v1/query?query=(time()-max%20by%20(instance)(restic_backup_timestamp))/86400' \
  | jq -r '.data.result[] | "\(.metric.instance): \(.value[1]|tonumber|floor) days"'
```

Inspect the repo read-only from norte to see the last snapshot's client host and
timestamp (all repos share the password `hunter2`):

```bash
ssh norte 'sudo -E env RESTIC_PASSWORD=hunter2 \
  RESTIC_REPOSITORY=/mnt/nas/sftp-chroots/romy/uploads/restic-repo \
  nix run nixpkgs#restic -- snapshots --latest 5 --no-lock'
```

Check the tailnet's view of the client machine — a backup can only run when the
laptop is on and connected. The snapshot list gives the client's Tailscale
hostname; query it from any node (`--json` exposes more than the text output):

```bash
tailscale status --json \
  | jq '.Peer[] | select(.HostName=="macbook-air-8") | {Online,LastSeen,KeyExpiry,Expired}'
```

Interpret it:

- **`Expired: true`** (with a past `KeyExpiry`) — the node key has expired, so the
  machine can't join until it re-authenticates. This is Tailscale's equivalent of
  a "cert expired"; note it's the node *key*, not a TLS cert. The plain
  `tailscale status` text view annotates such a peer with `; expired`. Fix is
  reauth on the client (or disable key expiry for that machine in the admin
  console). `KeyExpiry: null` means key expiry is disabled — not the problem.
- **`Online: false`** with a `LastSeen` around when backups stopped — the machine
  has just been off/away. Nothing to fix on the homelab side. (Backups can also
  run over the LAN without Tailscale, so `LastSeen` can predate the last snapshot;
  compare orders of magnitude, not exact times.)
- **`Online: true`** yet still stale — connectivity is fine, so the client's backup
  schedule itself is broken; chase it on their machine.

The tailnet view only tells you online/last-seen/expiry. It **cannot** tell you
*why* a client fails to connect — those diagnostics must run **on the client
machine**: `tailscale status` (is tailscaled up / logged in?),
`tailscale netcheck` (local network conditions), `tailscale ping <peer>` (actual
path, relay vs direct), and `journalctl -u tailscaled` / the Mac's launchd logs
for auth or key-expiry errors.

## Resolution

Client-side: nudge the person / check the backup job on their machine. There is
no config-as-code fix in this repo. The alert self-clears on the next successful
push. If a family laptop is routinely away >2 weeks, consider raising the
threshold in the rule rather than muting.

## Log

- 2026-07-22: `norte_romy` stale at 15d; last snapshot `macbook-air-8`
  2026-07-07; laptop offline on Tailscale ~3 weeks. Client-side, self-clears.
