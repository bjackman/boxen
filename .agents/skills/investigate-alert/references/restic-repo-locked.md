# ResticRepoLocked

**Rule:** `nixos_modules/prometheus/rules.nix`, group `Restic`. Fires on
`restic_locks_total > 0`, `for: 6h`, severity `warning`.

`instance` is `<host>_<repo>` (e.g. `norte_niamh`); see
[restic-backup-stale.md](restic-backup-stale.md) for the client-push topology
and the location of each repo.

## What it means

Restic takes a lock for the duration of any repo operation, so a lock that
survives 6h is a **stale lock left by a client that died mid-run** (laptop shut
or slept during a `backup`/`forget --prune`/`check`). The exporter just counts
files in `<repo>/locks`; it can't tell live from stale.

Two things determine how much it matters:

- **`exclusive: true`** — from `prune`/`forget --prune`/`rebuild-index`. Blocks
  everything, including backups.
- **`exclusive: false`** — from `backup`/`check`/`snapshots`. Only blocks
  exclusive operations, so backups keep working and the repo slowly accretes
  unprunable garbage.

Restic's own staleness detection only fires when the lock's `hostname` matches
the machine running the command *and* its `pid` is gone. So a stale lock is
usually invisible to the client that left it and permanently visible to
everything else — including this alert. Do not assume "alert firing" means
"backups blocked": check `restic_backup_timestamp` for the same instance.

## Diagnose

List the locks and read each one (all repos share the password `hunter2`; `sudo`
is needed because the chroots are owned by the SFTP user):

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

Once you've confirmed the owning process is dead, `restic unlock` clears it.
Prefer running it **on the client that left the lock** — that machine can reach
the repo over SFTP with its own credentials, and it's the one whose backup
schedule needs fixing anyway. Running it on norte as root also works.

There is no config-as-code fix; this is operational cleanup. The alert clears on
the next scrape after the lock file disappears.

## Log

- 2026-08-11: `norte_niamh` exclusive lock from `airbuntu` pid 467848 at
  2026-08-06T07:41+01:00, mtime never advanced. `norte_romy` non-exclusive lock
  from `macbook-air-8` at 2026-08-03T11:03+02:00, plus a `-restic-temp-` leftover
  from March. romy's backups kept running throughout (latest 2026-08-10);
  niamh's stopped the same day as the lock. Both stale, both need `unlock`.
