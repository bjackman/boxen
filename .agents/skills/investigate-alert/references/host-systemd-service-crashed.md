# HostSystemdServiceCrashed

**Rule:** `nixos_modules/prometheus/rules.nix`, group `Host`. Fires on
`node_systemd_unit_state{state="failed"} == 1`, joined to `node_uname_info` for
the `nodename` label. Severity `warning`.

The alert labels don't name the unit, so the first step is always to ask
Prometheus which one:

```bash
curl -s 'http://pizza:9090/api/v1/query?query=node_systemd_unit_state%7Bstate%3D%22failed%22%7D%3D%3D1' \
  | jq -r '.data.result[] | "\(.metric.instance) \(.metric.name)"'
```

Then get the failure itself:

```bash
ssh <host> 'systemctl status <unit> --no-pager -l'
ssh <host> 'journalctl -u <unit> --since "7 days ago" --no-pager | grep -Ei "starting|err|fail"'
```

The `--since` sweep matters more than the last invocation: for a timer-driven
unit it shows the **first** failing run, which dates the breakage and is what you
correlate against deploys and upstream changes.

## Triage

Distinguish three shapes:

- **Transient** — one failed run, later ones fine. The unit stays `failed` until
  something resets it, so the alert outlives the problem. Nothing to fix.
- **Host-local** — full disk, missing secret, dead dependency. Usually paired
  with another alert.
- **Upstream drift** — the unit hasn't changed but the data it pulls at runtime
  has. This is the one to watch for on norte: several units clone or fetch from
  the internet on each run, so a **pinned package plus a moving upstream** breaks
  without any deploy on our side. Tell: the breakage date matches an upstream
  commit, not a `git log` entry here.

For that last case, compare the deployed version against what the flake would
now build:

```bash
ssh <host> 'readlink -f /run/current-system'          # nixpkgs date is in the name
nix eval --raw .#nixosConfigurations.<host>.pkgs.<pkg>.version
```

A gap means the host is simply behind and a redeploy may be the whole fix — but
check the upstream break was a *version* incompatibility and not a *schema* one,
or the redeploy will fail differently. See the log below for exactly that trap.

## Resolution

Fix in code and let Brendan deploy (repo `CLAUDE.md`). `systemctl reset-failed
<unit>` clears the alert without fixing anything — only use it for a confirmed
transient.

## Log

- 2026-08-11: `recyclarr.service` on norte, failing nightly since 2026-08-08 with
  `templates.json does not exist: .../config-templates/includes.json`. Upstream
  `recyclarr/config-templates` merged its `v8` branch to `master` on 2026-08-07;
  recyclarr always tracks `master`, so norte's pinned 7.4.1 (nixpkgs
  25.11.20260514, deployed ~57d prior) broke with no local change. The flake now
  pins 8.6.0, but a plain redeploy is *not* sufficient: v8 deleted the
  `includes/` directory and the `include:`-composition model, so the six template
  IDs in `nixos_modules/arr.nix` (`radarr-quality-profile-uhd-bluray-web` etc.)
  no longer exist. The config needs porting to the v8 schema
  (`quality_profiles` + `custom_format_groups`, whole-config templates
  `uhd-bluray-web` / `web-1080p`).
