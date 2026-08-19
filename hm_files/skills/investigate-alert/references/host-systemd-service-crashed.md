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

Fix in code and let Brendan deploy (repo `CLAUDE.md`). `systemctl reset-failed <unit>` clears the alert without fixing anything — only use it for a confirmed
transient.

## Log

- 2026-08-11: `recyclarr.service` on norte, failing nightly since 2026-08-08 with
  `templates.json does not exist: .../config-templates/includes.json`. Upstream
  `recyclarr/config-templates` merged its `v8` branch to `master` on 2026-08-07;
  recyclarr always tracks `master`, so norte's pinned 7.4.1 (nixpkgs
  25.11.20260514, deployed ~57d prior) broke with no local change. Two separate
  fixes were needed, and a plain redeploy would have given neither:

  1. v8 deleted the `includes/` directory and the `include:`-composition model,
     so the six template IDs in `nixos_modules/arr.nix` no longer existed. Ported
     to the v8 schema (`quality_definition` + `quality_profiles` by `trash_id`),
     transcribing `radarr/templates/uhd-bluray-web.yml` and
     `sonarr/templates/web-1080p.yml`. `custom_formats` with `trash_ids` /
     `assign_scores_to` survives v8 unchanged, so the x265 score override stayed.
  1. **8.6.0 in stable nixpkgs is itself too old for the current templates** —
     it rejects `trash_id` on a quality profile
     (`Property 'trash_id' not found on type QualityProfileConfigYaml`). Pinned
     `services.recyclarr.package` to 8.7.0 from the flake's nixpkgs-unstable.
     This also surfaced that `pkgsUnstable` was a single x86_64 instance shared
     by every host, so aarch64 nodes were silently offered x86_64 packages;
     `flake.nix` now instantiates it per host.

  The lesson worth reusing: **validate a recyclarr config by running the real
  binary against it** before deploying. A dummy `api_key` is enough — parse and
  schema errors surface before the HTTP 401. Doing this on norte reuses its
  existing guide clones and keeps the download off a laptop:

  ```bash
  ssh norte 'bash -c "mkdir -p /tmp/rc-validate/repositories
    sudo cp -r /var/lib/recyclarr/repositories/* /tmp/rc-validate/repositories/
    sudo chown -R brendan /tmp/rc-validate
    RECYCLARR_CONFIG_DIR=/tmp/rc-validate RECYCLARR_DATA_DIR=/tmp/rc-validate \
      nix run nixpkgs#recyclarr -- sync --config /tmp/rc-config.yml --preview"'
  ```
