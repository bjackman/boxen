# ResticRepoLocked

**Rule:** `nixos_modules/prometheus/rules.nix`, group `Restic`. Fires on
`restic_locks_total > 0`, `for: 6h`, severity `warning`.

`instance` is `<host>_<repo>` (e.g. `norte_niamh`); see
[restic-backup-stale.md](restic-backup-stale.md) for the client-push topology
and the location of each repo.

## What it means

Restic takes a lock for the duration of any repo operation and refreshes it
every 5 minutes. A lock that hasn't been refreshed for 30 minutes is stale, from
any host's point of view. But restic never removes stale locks on its own, and
taking a new lock doesn't skip them. Only `restic unlock` clears them.

norte runs `restic-unlock-<user>.service` hourly against each repo, so a client
that died mid-run (laptop shut or slept during `backup`/`forget --prune`) should
only cause a brief blip. A lock that survives 6h means one of two things:

- **The unlock unit is failing.** Look at it first.
- **An operation really has been running that long.** Its lock file's mtime
  keeps advancing.

The exporter just counts files in `<repo>/locks` and refreshes hourly. It can't
tell live locks from stale ones.

Two things determine how much it matters:

- **`exclusive: true`** — from `prune`/`forget --prune`/`rebuild-index`. Blocks
  everything, including backups.
- **`exclusive: false`** — from `backup`/`check`/`snapshots`. Only blocks
  exclusive operations, so backups keep working and the repo slowly accretes
  unprunable garbage.

Do not assume "alert firing" means "backups blocked": check
`restic_backup_timestamp` for the same instance.

## Diagnose

Start with the unlock unit:

```bash
slop-probe norte unit-status --unit=restic-unlock-niamh.service
slop-probe norte journal --unit=restic-unlock-niamh.service --since=-2d
```

slop-probe can't read the locks, but you can usually infer what they are without
reading them. Compare the lock count and snapshot history from Prometheus
(`restic_locks_total`, `max by (instance)(restic_backup_timestamp)` over
`query_range`) with the client's SFTP logins:

```bash
slop-probe norte journal --identifier sshd-session \
  --grep 'Accepted publickey for niamh ' --since=-40d --output short-iso | sort
```

Each healthy run logs in a fixed number of times, so find that number on a day
with a new snapshot. It's four for niamh and two for romy (`backup`, then
`forget --prune`). Here's how to read the patterns:

- **A run that falls short of the healthy count, then a lock, after a new
  snapshot:** the prune died, leaving an exclusive lock.
- **A single daily login with no new snapshot from then on:** an exclusive lock
  is turning each run away at its first step.
- **A lock appears with no new snapshot:** the `backup` itself died, leaving a
  non-exclusive lock. That lock then blocks the prune.

To be certain, list the locks and read each one. This needs SSH to norte, which
slopbox doesn't have. All repos share the password `hunter2`, and `sudo` is
needed because the chroots are owned by the SFTP user:

```bash
ssh norte "bash -c 'export RESTIC_PASSWORD=hunter2
R=/mnt/nas/sftp-chroots/niamh/uploads/restic-repo
for id in \$(sudo -E nix run nixpkgs#restic -- -r \$R --no-lock list locks); do
  sudo -E nix run nixpkgs#restic -- -r \$R --no-lock cat lock \$id
done'"
```

Always pass `--no-lock`; without it `cat lock` tries to take its own lock and
dies with `repo already locked` when the stale one is exclusive — which is
itself the tell that you're looking at an exclusive lock.

The JSON gives `time`, `exclusive`, `hostname`, `pid`. Cross-check against the
lock file's mtime:

```bash
ssh norte 'sudo ls -la /mnt/nas/sftp-chroots/niamh/uploads/restic-repo/locks/'
```

Restic refreshes a live lock every ~5 minutes, so **mtime == the `time` field
means the process died right after taking it**. An mtime that keeps advancing
means an operation really is still running — leave it alone.

Also look for leftovers named `<id>-restic-temp-<hex>`: partial uploads from an
interrupted transfer. They are not locks and `unlock` won't remove them; delete
them by hand once you're sure nothing is running.

Then decide whether it's actually hurting:

```bash
curl -s 'http://pizza:9090/api/v1/query?query=(time()-max%20by%20(instance)(restic_backup_timestamp))/86400' \
  | jq -r '.data.result[] | "\(.metric.instance): \(.value[1]|tonumber|floor) days"'
```

## Resolution

Stale locks should never need clearing by hand: if one outlives the hourly
`restic-unlock-<user>` run, fix that unit. Don't reach for `unlock --remove-all`.
Plain `unlock` already removes every lock older than 30 minutes, so anything it
leaves behind is a lock that's still being refreshed.

The lock is a symptom of the client dying mid-run, and that's on the client side
(`hm_modules/<user>.nix`). Repeated deaths are worth chasing even once the lock
clears itself. The alert clears on the exporter's next hourly refresh after the
lock file disappears.

## Log

- 2026-08-11: `norte_niamh` exclusive lock from `airbuntu` pid 467848 at
  2026-08-06T07:41+01:00, mtime never advanced. `norte_romy` non-exclusive lock
  from `macbook-air-8` at 2026-08-03T11:03+02:00, plus a `-restic-temp-` leftover
  from March. romy's backups kept running throughout (latest 2026-08-10);
  niamh's stopped the same day as the lock. Both stale, both need `unlock`.

- 2026-10-13: Both again, with neither lock read: the state was inferred from
  logins and metric history alone.

  niamh: on 2026-10-05 06:54Z there were three logins out of the healthy four.
  The snapshot landed and a lock appeared, so the prune died and left an
  exclusive lock. After that came one login a day and no snapshots. This was a
  separate incident from 2026-08-11. After that unlock, niamh backed up until
  2026-08-14, then stopped again. A lock was already present when Prometheus's
  history began (2026-09-28), and it cleared on 2026-10-02.

  romy: on 2026-10-05 and 2026-10-08 the `backup` started and the `forget`
  login came 1-8h later, with no snapshot and a new lock each time. So the
  backups were dying mid-run, leaving non-exclusive locks.

  That prompted the hourly `restic-unlock-<user>` units. The earlier claim here,
  that restic only treats a lock as stale on the host that took it, was wrong:
  see `Lock.Stale()` in restic's `internal/restic/lock.go`.
