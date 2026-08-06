# Forgejo

**Status: proposal, not implemented.** Nothing in this document exists in the
\*repo yet. Partially reviewed but needs more thought, in particular about where
\*to run CI (Pizza's disk is too small).

## Goals

1. Canonical Git hosting in the homelab, for `boxen` and the other personal repos.
1. Mirrored to GitHub, so public links keep working and there's a free offsite copy of the
   code.
1. CI on push and on proposed changes.
1. Coding agents propose changes for review instead of pushing to `master`. Gerrit-style
   (no branch clutter, no fork) is preferred.

## Background

[Forgejo](https://forgejo.org) is a Gitea fork; nixpkgs 26.05 has `forgejo` 16.0.1 and a
mature NixOS module (`services.forgejo`), plus `forgejo-runner` 12.13.2 driven by
`services.gitea-actions-runner` (note: `pkgs.forgejo-actions-runner` was renamed to
`pkgs.forgejo-runner`; the *module* is still called `gitea-actions-runner` and takes a
`package` argument).

Three Forgejo features do most of the work here:

- **Push mirrors.** A repo can be configured to push all branches and tags to a remote on
  a schedule and/or on every push. This is how the GitHub copy stays current. It's
  one-way and force-based: GitHub is a dumb replica.
- **Forgejo Actions.** GitHub-Actions-compatible, same YAML, `.forgejo/workflows/`. The
  runner supports a `host` execution mode that runs jobs directly on the runner machine
  rather than in a container — which is what we want, because the interesting jobs are Nix
  builds and they should hit a warm local store.
- **AGit flow.** `git push origin HEAD:refs/for/master -o topic=foo` creates or updates a
  PR without creating a branch in the repo and without a fork. Re-pushing the same topic
  adds a new version of the change, with a diff between versions in the UI. This is the
  Gerrit-shaped workflow, and it's the right shape for agents: they don't need write
  access to any branch namespace at all.

### What already exists in the repo that this plugs into

- `nixos_modules/iap.nix` — Caddy + Authelia on `pizza`, wildcard cert for
  `*.home.yawn.io`. `home.yawn.io` resolves to the **public** IP (ddclient/Cloudflare), so
  anything registered in `bjackman.iap.services` is internet-facing.
- `nixos_modules/ports.nix` — automatic port allocation.
- `nixos_modules/postgres.nix` — Postgres on `pizza`, already used by miniflux and
  bitmagnet.
- `nixos_modules/silverbullet.nix` — the restic-to-`norte`-over-SFTP backup pattern.
  Deliberately *not* reused here; see decision 7.
- `nixos_modules/slopbox.nix` + `tf/slopbox/` — an Incus VM on `chungito` for letting
  agents run loose. Reusable as CI-runner isolation later.
- `packages/slopclone` — the current "give the agent a scratch clone" hack. Forgejo makes
  this mostly redundant.
- `limmat.toml` — local pre-merge CI (`nix flake check`, `format`). The Forgejo CI is the
  same checks, but running on changes that arrive from somewhere other than my keyboard.

### Hardware constraints (measured)

| Host | CPU | RAM | Free disk | Notes |
| --- | --- | --- | --- | --- |
| `pizza` | 8 × T480 | 8 GB | 68 G of 230 G | Always on. Runs the IAP, Postgres, Jellyfin. |
| `norte` | 4 × Pi5 (aarch64) | 8 GB | 750 G on `nas` | Always on, but weak and already busy. |
| `chungito` | 16 | 62 GB | — | Workstation. Fast, but not always on. |

Forgejo itself is small (a few hundred MB RSS, repos are tiny). Nix builds are not. That
split drives decision 6.

## Decisions

1. **Forgejo is canonical; GitHub is a push mirror.** The alternative — GitHub canonical
   with Forgejo pull-mirroring — makes the self-hosted side read-only, which defeats goals
   3 and 4. The cost is that GitHub-side issues and PRs don't sync back; see "Gotchas".

1. **Host: `pizza`.** It's where the IAP, Postgres and every other web service live, it's
   always on, and it's x86_64. `norte` has the storage but git repos don't need bulk
   storage, and it's an already-loaded aarch64 Pi.

1. **Git is SSH-only by convention, not by kill-switch.** Everything I drive — my clones,
   the agents' AGit pushes — goes over SSH, and the clone URLs in the UI are SSH URLs.
   But `[repository] DISABLE_HTTP_GIT = true` stays **off**, because it and Forgejo
   Actions are mutually exclusive: `actions/checkout` clones over HTTP using the job's
   task token, and `HTTPGitEnabledHandler` 403s every git-over-HTTP route unconditionally
   with no exemption for Actions tokens (checked in
   `routers/web/repo/githttp.go`). Turning it on breaks CI checkout.

   `[service] ENABLE_BASIC_AUTHENTICATION = false` is under the same cloud and also stays
   off pending a test: git-over-HTTP authenticates through the basic-auth path, and the
   Actions task token rides that same path (`ctx.IsBasicAuth && ... !ctx.Doer.IsGiteaActions()`
   in `httpBase()`). It *may* be that the setting only disables password-over-basic and
   leaves tokens working, which is what the docs' wording suggests — but that needs
   verifying against a live instance, not inferring.

   So the git-over-HTTP surface stays enabled and is kept off the internet by the Caddy IP
   allowlist below, rather than by a Forgejo setting. Slightly less satisfying, but the
   endpoint isn't publicly reachable either way, and it keeps CI working with stock
   actions.

   What SSH-only *does* buy unconditionally: AGit runs over its well-trodden SSH path, and
   `slopbot`'s primary credential is an SSH key rather than a token.

1. **Exposure: direct reverse proxy (`oidc.enable = true`), plus a source-IP restriction
   to Tailscale and LAN.** The default `forward_auth` is *still* not an option even with
   git on SSH, because two non-browser HTTP clients remain: the Actions runner (which
   polls `/api/actions`) and whatever reads the API — the reconciliation oneshot, and
   agents fetching review comments on their own PRs. None of those can follow Authelia's
   login redirect. So Forgejo authenticates itself, via Authelia OIDC, like Jellyfin does.

   But unlike Jellyfin, Forgejo holds the crown jewels and is a large Go web app with a
   real CVE history, and `*.home.yawn.io` is on the public internet. So this also wants an
   IP allowlist in Caddy (Tailscale CGNAT `100.64.0.0/10` + LAN + loopback). Everything
   that needs to reach it — my machines, the runner, the agent VM — is on Tailscale
   already. This needs a small new option in `iap.nix`; see the design below.

   **Rejected alternative: `forward_auth` + `[service] ENABLE_REVERSE_PROXY_AUTHENTICATION`.**
   Tempting, because Forgejo would then trust Caddy's `Remote-User` header exactly like
   miniflux trusts `AUTH_PROXY_HEADER`, and the entire OIDC setup below — a non-declarative
   oneshot plus two secrets — evaporates.

   It doesn't work here, and the reason is worse than I first assumed. I'd guessed
   `[security] REVERSE_PROXY_TRUSTED_PROXIES` (default `127.0.0.0/8,::1/128`) would gate
   it. It doesn't: `ReverseProxy.Verify()` in `services/auth/reverseproxy.go` reads the
   header and returns the user with **no peer-address check at all**, and the code comment
   says so outright — "Verification of header data is not performed as it should have
   already been done by the reverse proxy." `REVERSE_PROXY_TRUSTED_PROXIES` governs
   `X-Forwarded-For` client-IP resolution, which is a different thing.

   (Read in the Gitea tree — Codeberg's raw endpoint 404'd on both branch names I tried.
   Forgejo forks this file, so confirm before relying on it.)

   So with reverse-proxy auth on, *anything* that can open a TCP connection to Forgejo's
   HTTP port is one header away from an admin session. The runner needs to reach that port
   from another host. That's the end of the idea: there is no configuration that gives the
   runner access and denies it to everything else on the same network. The variant where
   Caddy exempts `/api/*` from `forward_auth` and strips the `Remote-*` headers on that
   route is sound in principle and one typo away from an internet-facing admin bypass.
   OIDC's worst failure mode is "login stops working"; this one's is "someone owns the
   forge".

1. **Database: Postgres over the unix socket**, reusing the existing instance via
   `imports = [ ./postgres.nix ]`, with `database.createDatabase = true` so the module
   sets up peer auth and no password file is needed. SQLite would also be fine for a
   single-user forge, but Postgres is already there and `services.forgejo.dump` handles
   either.

1. **No backups. The GitHub mirror is the copy of record.** Every branch and tag of every
   mirrored repo is continuously replicated to a third party for free, which covers the
   only thing here that's genuinely expensive to recreate: history. Adding restic on top
   would back up a strictly smaller amount of *valuable* data than the mirror already
   does, at the cost of another timer, another agenix secret, another
   `restic-exporter` instance, and another alert that can go stale and want attention.

   What this consciously does *not* protect, in descending order of how much I'd care:

   - **Open pull requests, including agent AGit PRs.** Push mirrors replicate
     `refs/heads/*` and tags; PR refs live under `refs/pull/*`, which GitHub refuses to
     accept ("deny updating a hidden ref" — the namespace is read-only there). So the
     review queue is not replicated anywhere. Judged acceptable because an unreviewed
     agent PR is cheap to regenerate: re-run the agent.
   - **Issues, comments and review threads.** Gone in a disaster. I don't currently track
     anything in a forge issue tracker; if that changes, this decision should be revisited
     rather than silently inherited.
   - **Actions run history and logs.** Don't care.

   **This decision is load-bearing on decision 9.** The reason losing `/var/lib/forgejo`
   is survivable is that the users, SSH keys, mirror configs, branch protections and
   collaborator lists are reconciled from Nix, so recovery is "redeploy `pizza`, let the
   oneshot rebuild the state, re-import repos from GitHub". If that ever degrades into
   clicking things in the UI, the no-backup call quietly becomes wrong. Worth remembering
   as a pair.

   Separately and unrelatedly: `/var/lib/forgejo` still needs a
   `bjackman.impermanence.extraPersistence` entry. That's about surviving a reboot, not a
   disaster, and is not optional.

   If the PR queue ever does start to matter, the cheap escalation is *not* restic — it's
   `services.forgejo.dump` with `backupDir` pointed at `/mnt/nas-media/forgejo`, which is
   already a CIFS mount to `norte`'s ZFS with 475 G free. Three lines, no new secret, no
   new alert, and the metadata lands on a different machine under ZFS snapshots.

1. **CI runner: on `chungito`, `host` mode, one runner.** Nix builds want cores, RAM and a
   warm store; `pizza` has 8 GB and 68 G of disk and would spend its life thrashing and
   then fill up. `chungito` already has `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`
   (from `common.nix`) so it can build the Pi configs too, and `nix flake check` filters
   the checks to the host system anyway.

   The accepted downside: CI only runs when the workstation is on. Jobs queue rather than
   fail, which I think is fine — this isn't a team.

   `host` mode means jobs execute as the runner's user on the workstation with no
   container boundary. Only I and my agents can push, so this is a judgement call rather
   than an outrage, and the module runs the runner under `DynamicUser`. If that stops
   feeling OK — e.g. if I ever accept a PR from a stranger and it runs CI — the escalation
   path is a dedicated Incus VM on `chungito` built exactly like `slopbox`.

1. **Agent changes arrive by AGit, from a dedicated `slopbot` user, with `master`
   protected.** The security property I actually want is "an agent cannot alter history on
   `master`", and that's a branch protection rule, not a matter of trust. AGit means the
   agent needs no branch write access at all and leaves no `slop/fix-thing-v3` litter.

1. **Repo, mirror and branch-protection setup is reconciled from Nix, not clicked in the
   UI.** These are per-repo runtime state in Forgejo's DB, which is exactly the kind of
   thing this repo tries not to have. A oneshot unit that PUTs a Nix-defined attrset
   through the API keeps it in code.

## Design

### `nixos_modules/iap.nix`: source-range restriction

New per-service option:

```nix
allowedSourceRanges = lib.mkOption {
  type = with lib.types; nullOr (listOf str);
  default = null;
  description = ''
    If set, reject requests whose source IP isn't in one of these CIDRs. Note this
    is evaluated on the direct peer, which is correct because Caddy is the edge.
  '';
};
```

and in the generated vhost, inside each service's `handle` block:

```
${lib.optionalString (service.allowedSourceRanges != null) ''
  @${service.subdomain}_denied not remote_ip ${lib.concatStringsSep " " service.allowedSourceRanges}
  respond @${service.subdomain}_denied 403
''}
```

Worth defining a `tailscaleAndLan` list somewhere shared: `100.64.0.0/10`,
`192.168.1.0/24`, `127.0.0.0/8`, `::1`, and the Tailscale IPv6 ULA `fd7a:115c:a1e0::/48`.

### `nixos_modules/forgejo.nix`

```nix
{ config, lib, pkgs, ... }:
let
  port = config.bjackman.ports.forgejo.port;
  sshPort = 2222;
  url = config.bjackman.iap.services.forgejo.url;
in
{
  imports = [ ./ports.nix ./iap.nix ./postgres.nix ./impermanence.nix ];

  bjackman.ports.forgejo = { };

  bjackman.iap.services.forgejo = {
    port = port;
    oidc.enable = true;
    allowedSourceRanges = [ "100.64.0.0/10" "192.168.1.0/24" "127.0.0.0/8" ];
    oidc.autheliaConfig = { /* as per jellyfin.nix; redirect_uri is
        "${url}/user/oauth2/authelia/callback" */ };
  };

  services.forgejo = {
    enable = true;
    database.type = "postgres";      # socket + peer auth, createDatabase defaults true
    lfs.enable = true;
    # No `dump`: see decision 7.
    settings = {
      server = {
        DOMAIN = "forgejo.home.yawn.io";
        ROOT_URL = "${url}/";
        # Not 127.0.0.1: the runner on chungito talks to pizza directly over
        # Tailscale rather than hairpinning through the public IP (which the
        # allowedSourceRanges above would reject anyway).
        HTTP_ADDR = "0.0.0.0";
        HTTP_PORT = port;
        START_SSH_SERVER = true;
        SSH_DOMAIN = "pizza";
        SSH_PORT = sshPort;
        SSH_LISTEN_PORT = sshPort;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        # UI login is Authelia-only. Renamed from ENABLE_PASSWORD_SIGNIN_FORM;
        # 16.0.1 wants this spelling.
        ENABLE_INTERNAL_SIGNIN = false;
        # ENABLE_BASIC_AUTHENTICATION stays at its default of true: the Actions
        # task token clones through the basic-auth path. See decision 4.
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        USERNAME = "preferred_username";
      };
      actions.ENABLED = true;
      mirror.ENABLED = true;
      metrics.ENABLED = true;
      # DISABLE_HTTP_GIT deliberately left at false; see decision 4.
      repository.DEFAULT_BRANCH = "master";
    };
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ port sshPort ];
}
```

Add to `nixos_modules/pizza/default.nix`'s imports, and to `homelab.servers` in
`flake.nix` if anything else needs to find it.

### OIDC auth source

The one part that isn't declarative. Forgejo stores login sources in the DB and there is no
`app.ini` equivalent, so it needs a oneshot after `forgejo.service`:

```nix
systemd.services.forgejo-oidc = {
  after = [ "forgejo.service" ];
  requires = [ "forgejo.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    User = "forgejo";
    ExecStart = pkgs.writeShellScript "forgejo-oidc" ''
      args=(--name authelia --provider openidConnect
            --key "$CLIENT_ID" --secret "$(cat $CREDENTIALS_DIRECTORY/secret)"
            --auto-discover-url ${config.bjackman.iap.autheliaUrl}/.well-known/openid-configuration
            --scopes "openid profile email groups")
      if forgejo admin auth list | grep -qw authelia; then
        id=$(forgejo admin auth list | awk '$2 == "authelia" { print $1 }')
        forgejo admin auth update-oauth --id "$id" "''${args[@]}"
      else
        forgejo admin auth add-oauth "''${args[@]}"
      fi
    '';
  };
};
```

Note Authelia stores the client secret *hashed* (see `jellyfin.nix`) while Forgejo needs
the plaintext, so this is two agenix secrets, as with Jellyfin.

**Lockout risk:** with `ENABLE_INTERNAL_SIGNIN = false`, if Authelia breaks there's no web
login. Recovery is `forgejo admin user ...` over SSH on `pizza`, which is fine, but worth
knowing before turning it on.

### SSH

Since SSH is now the *only* way git traffic reaches Forgejo, the choice of SSH server
deserves more thought than it otherwise would.

Two options:

1. **Forgejo's built-in Go SSH server** (`START_SSH_SERVER = true`, port 2222), as in the
   sketch above. Self-contained: it never touches `nixos_modules/ssh-server.nix`, and
   Forgejo's key handling is entirely its own business.
1. **The host's OpenSSH**, which is what the nixpkgs module wires up when
   `START_SSH_SERVER = false` — it adds an `AuthorizedKeysCommand` so `sshd` asks Forgejo
   which keys are valid. Gets you OpenSSH's hardening rather than Go's `crypto/ssh`, and
   port 22 so clone URLs need no port suffix.

Going with (1). The coupling in (2) is the problem: a botched `AuthorizedKeysCommand`
degrades into a strange failure in the box's real sshd, and `pizza`'s sshd is how I fix
`pizza`. The built-in server's blast radius is Forgejo itself.

Either way the port is only open on `tailscale0`, so this isn't internet-facing.

### Repo / mirror / protection reconciliation

A Nix attrset describing the repos:

```nix
bjackman.forgejo.repos = {
  boxen = {
    mirrorTo = "https://github.com/bjackman/boxen.git";
    protectedBranches = [ "master" ];
    collaborators.slopbot = "write";
  };
  limmat = { mirrorTo = "https://github.com/bjackman/limmat.git"; ... };
};
```

driven through a oneshot that hits the API with an admin token from agenix:

- `POST /api/v1/user/repos` (idempotent-ish: 409 on exists, ignore)
- `POST /api/v1/repos/{owner}/{repo}/push_mirrors` with `remote_address`,
  `remote_username = "bjackman"`, `remote_password = <GitHub PAT>`, `interval = "8h0m0s"`,
  `sync_on_commit = true`
- `POST /api/v1/repos/{owner}/{repo}/branch_protections` with `rule_name = "master"`,
  `enable_push = false` for everyone except me, `enable_merge_whitelist`, etc.
- `PUT /api/v1/repos/{owner}/{repo}/collaborators/slopbot`

The GitHub side needs a fine-grained PAT with **Contents: read/write** on the mirrored
repos only. Store it with agenix.

Doing this in a shell script with `curl` + `jq` is unpleasant but small; the alternative is
another OpenTofu module (there is a `terraform-provider-forgejo`) alongside `tf/arr`, which
is arguably the more honest fit given `tf/` already exists for exactly this
"reconcile runtime state of a service" job. Either way, not by hand in the UI.

### CI

`nixos_modules/forgejo-runner.nix`, imported by `chungito`:

```nix
services.gitea-actions-runner = {
  package = pkgs.forgejo-runner;
  instances.chungito = {
    enable = true;
    name = "chungito";
    # Direct to the host, not through Caddy — Caddy's vhost can't serve a client
    # that doesn't do the Authelia redirect. `pizza` resolves over both the LAN
    # and Tailscale; the LAN path is the one that matters (see below).
    url = "http://pizza:${toString homelab.nodes.pizza.bjackman.ports.forgejo.port}";
    tokenFile = config.age.secrets.forgejo-runner-token.path;   # env file: TOKEN=...
    labels = [ "nix:host" ];
    hostPackages = with pkgs; [
      bash coreutils curl gawk gitMinimal gnused nodejs wget
      nix          # the entire point
    ];
  };
};
```

The registration token comes from `forgejo actions generate-runner-token` on `pizza`
(or the admin UI) and goes into agenix. Note the module forces re-registration when the
token or labels change, so changing `labels` later is not free.

The runner runs under `DynamicUser`, which is fine for Nix: it talks to the daemon like
any unprivileged user and doesn't need to be a trusted user.

**Runner reachability.** `chungito` is on the LAN with `pizza` (192.168.1.0/24) as well as
on the tailnet, so the runner talks to Forgejo LAN-locally and CI doesn't depend on
Tailscale being healthy. That means the firewall rule for the HTTP port can be
LAN-scoped rather than `tailscale0`-scoped:

```nix
networking.firewall.interfaces."<lan-iface>".allowedTCPPorts = [ port ];
```

Don't over-read this as isolation, though. `slopbox` NATs out through `chungito`, so
anything in the agent VM reaches `pizza` at `chungito`'s LAN address regardless — a
LAN-scoped rule does not put the agent VM outside the boundary. It's a smaller blast
radius than the whole tailnet, not a meaningful containment story. The containment story
is that Forgejo authenticates every request itself (decision 3).

`.forgejo/workflows/check.yaml` in `boxen`:

```yaml
on: [push, pull_request]
jobs:
  flake-check:
    runs-on: nix
    steps:
      - uses: actions/checkout@v5
      - run: nix flake check -L
```

`@v5`, not `@v6`: v6 hardcodes GitHub Actions runner paths in its `includeIf.gitdir`
directives and is broken on non-GitHub forges. Also note the runner fetches action
definitions from `code.forgejo.org` by default — `[actions] DEFAULT_ACTIONS_URL` controls
this, and leaving it at the default means CI has an external dependency on someone else's
forge being up.

That's the same coverage as `limmat.toml` (`nix flake check` already builds every
system-matching `nixosConfiguration`, every `homeConfiguration`, and the `format` check).
`limmat` stays as the fast local loop; Actions is for changes that didn't come from my
keyboard.

**CD is deliberately out of scope for v1.** Per the repo's own rules I deploy by hand. If
that changes later, the shape is a `workflow_dispatch`-only job that runs `deploy-rs`,
gated on a manual trigger — not something that fires on merge.

### Agent workflow

Setup:

- A `slopbot` Forgejo user (created by the bootstrap oneshot, `must_change_password = false`, no admin) with:
  - **An SSH key**, registered via `POST /api/v1/admin/users/slopbot/keys`. This is the
    credential that matters — with git on SSH it's what does all the cloning and pushing.
  - **A scoped access token** (`read:repository`, `write:issue`), only so the agent can
    read review comments on its own PRs and reply. Not needed to *create* a PR: AGit does
    that from the push itself. Note Forgejo tokens are scoped by *capability*, not by
    repo — the per-repo limit comes from which repos `slopbot` is a collaborator on. Keep
    that list short.
- Both live in agenix and are injected into the agent environment (`slopbox`, or wherever
  an agent is running) — not into any always-on service.
- `master` protected: no direct pushes, PRs only.

The agent then does:

```
git clone ssh://git@pizza:2222/bjackman/boxen.git
# ... work ...
git push origin HEAD:refs/for/master \
    -o topic=fix-tvheadend-module \
    -o title="tvheadend: Add NixOS module" \
    -o description="..."
```

which creates a PR with no branch. Iterating means pushing the same topic again; Forgejo
records it as a new version and shows the inter-version diff — the Gerrit patchset
experience. CI fires on the PR, so I see a build result before I read the code.

This makes `packages/slopclone` mostly obsolete: the agent's scratch space is a clone of
the forge, and the review surface is a PR rather than a `slop` remote I have to go
fetch from.

### Monitoring

`[metrics] ENABLED = true` exposes `/metrics` (bearer token via `metrics.TOKEN`). Add a
scrape job in `nixos_modules/prometheus/`. Alerts worth having: Forgejo down, and — given
decision 7 makes the mirror the only copy — **mirror sync failure**. That second one is
now the important alert rather than a nice-to-have: a silently broken mirror means no
backup at all, and it would fail open and quiet. Forgejo surfaces sync status in the UI;
whether there's a usable metric for it needs checking, and if there isn't, that's worth a
small scripted check instead.

## Gotchas and open questions

- **Push mirrors are one-way and lossy.** GitHub issues and PRs on the mirrors won't sync
  back. Options: turn issues/PRs off on the GitHub side and put a "mirror of
  forgejo.home.yawn.io, please email me" note in the README, or accept them and merge by
  hand. Since these repos get roughly zero external contributions, either is fine, but it
  should be a conscious choice — and `limmat` has actually had outside interest, so maybe
  that one stays GitHub-canonical.
- **Push mirroring force-pushes.** If something ever writes to GitHub directly, it gets
  clobbered silently on the next sync.
- **Expect rejected-ref noise on every sync.** Gitea/Forgejo push mirrors use `--mirror`
  semantics, so they attempt `refs/pull/*` too, and GitHub rejects that namespace outright.
  Need to confirm whether Forgejo filters these out or whether each sync reports a partial
  failure — because if it's the latter, "the mirror is failing" and "the mirror is fine"
  look identical, and decision 7 depends on being able to tell them apart.
- **A repo with no mirror configured has no backup at all.** Under decision 7 this goes
  from untidy to data-loss. The reconciliation oneshot should treat a repo that exists in
  Forgejo but not in the Nix attrset as an error worth surfacing, not something to ignore.
- **`master` vs `main`.** GitHub's default for new repos is `main`; existing mirrors keep
  whatever they have. Set `repository.DEFAULT_BRANCH = "master"` to match this repo.
- **Hairpin NAT.** `forgejo.home.yawn.io` resolves to the public IP everywhere, including
  from inside the LAN. Whether the UDR7 hairpins correctly is untested. Git is unaffected
  (SSH goes to `pizza` by name over Tailscale), so this is only about reaching the web UI
  from the LAN-but-not-Tailscale case. Split-horizon DNS on the UDR7 would fix it
  properly. Related open item in the UDR7 notes about DNS.
- **The IP allowlist and Cloudflare.** If `home.yawn.io` ever goes behind a Cloudflare
  proxy the `remote_ip` matcher starts seeing Cloudflare's IPs and the allowlist silently
  becomes an allow-all. Currently DNS-only, so fine.
- **Runner-to-Forgejo over plain HTTP.** Over Tailscale, so encrypted in transit anyway.
  Mildly ugly; the alternative is a cert Forgejo serves itself.
- **Disk.** `pizza` has 68 G free. Forgejo Actions stores artifacts and logs under
  `/var/lib/forgejo`; artifacts should stay off or be capped, and `actions.LOG_RETENTION_DAYS`
  set low. LFS likewise — enabled above, but nothing currently needs it.
- **Migration order.** Push `boxen` to Forgejo → set up the mirror → verify GitHub gets the
  push → repoint the local remote → repeat per repo. Keep GitHub as a live mirror
  throughout, so a Forgejo disaster costs at most the metadata.
- **Verify AGit push options early.** The whole agent story rests on `-o topic=`/`-o title=`
  being accepted, and on re-pushing a topic producing a new version rather than an error.
  SSH is the well-trodden path for this, but check it before building anything on top.
- **Test `ENABLE_BASIC_AUTHENTICATION = false` against a live instance** before assuming
  it can be turned on. If Actions checkout survives it, take it — it's free surface
  reduction. If not, leave it.
- **The git-over-HTTP surface is protected only by the Caddy allowlist and the firewall**,
  not by a Forgejo setting (decision 4). That makes those two rules load-bearing in a way
  they wouldn't otherwise be. Worth an actual `curl` from off-network after deploying,
  rather than trusting the config to say what it means.
