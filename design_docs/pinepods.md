# PinePods

**Status: not implemented.** This is a design that was worked out and then shelved. It's
written down so that if I pick it up later I don't have to redo the investigation. Nothing
in this document exists in the repo yet.

## Background

[PinePods](https://pinepods.online) is a self-hosted podcast management server and player.
The goal was to run it in the homelab as a native NixOS service, packaged in this repo
under `packages/`, using the PostgreSQL instance that the other apps on `pizza` already
share.

Upstream only ships a Docker image
([madeofpendletonwool/PinePods](https://github.com/madeofpendletonwool/PinePods)), and
their [install docs](https://pinepods.online/docs/intro#installing-runner) are entirely
docker-compose based. There is no NixOS module in nixpkgs.

### What PinePods actually is

This is the part that took the investigation. The single Docker image is really four
programs behind an nginx, supervised by [horust](https://github.com/FedericoPonzi/Horust).
Everything below was checked against upstream commit `4b8785b5` (2026-07-10) — see
`dockerfile`, `startup/startup.sh`, `startup/services/*.toml` and `startup/nginx.conf` in
that repo.

| Component | Source dir | Build system | Role |
| --- | --- | --- | --- |
| `pinepods-api` | `rust-api/` | cargo (axum, sqlx) | The backend. Listens on a **hardcoded** `0.0.0.0:8032` (`rust-api/src/config.rs:269`). |
| web UI | `web/` | Yew → wasm via `trunk` | Static files. **Not** served by the API — nginx serves them. |
| `gpodder-api` | `gpodder-api/` | go 1.25 | gpodder.net sync protocol. Port from `SERVER_PORT`, container uses 8042. |
| db setup | `startup/setup_database_new.py` + `database_functions/` | python 3.11 | Idempotent migration runner. Upstream freezes it into a binary with PyInstaller purely to avoid shipping python in the image. |
| nginx | `startup/nginx.conf` | — | Serves the UI and routes `/api`, `/rss`, `/ws` and the gpodder paths. Genuinely required. |

Runtime dependencies beyond that: PostgreSQL (18 recommended, 17 works — the schema is
plain SQL created by the migration runner), Valkey/Redis for caching (mandatory — the API
refuses to start without `VALKEY_HOST`/`VALKEY_PORT` or `VALKEY_URL`), and `yt-dlp`,
`ffmpeg`, `pg_dump`, `psql`, which the API shells out to.

### Gotchas found during investigation

- **Hardcoded FHS paths in the Rust API.** `/opt/pinepods/{downloads,backups,local-media,certs}`,
  `/var/www/html/static/translations` (`handlers/settings.rs:5709`),
  `/var/www/html/static/assets/favicon.png` (`handlers/settings.rs:1107`), and
  `/pinepods/current_version` (`database.rs:3027`). None are configurable.
- **The API only speaks TCP + password to Postgres.** `DB_HOST`, `DB_PORT`, `DB_USER`,
  `DB_PASSWORD`, `DB_NAME` are all mandatory (`rust-api/src/config.rs:145`); there is no
  unix-socket or peer-auth path. Same for the python setup script.
- **The python setup script connects to the `postgres` database first** to check whether
  the target DB exists and `CREATE DATABASE` it if not. If the DB is pre-created it just
  finds it and moves on, so no `CREATEDB` privilege is needed.
- **The python code's mariadb imports are all behind `try/except`**, so a
  postgres-only python env is fine. It needs `psycopg`, `passlib`, `argon2-cffi`,
  `cryptography`, `python-dateutil`, `pytz`.
- **`web/Cargo.lock` pins `wasm-bindgen` 0.2.125**, and the CLI version must match the
  crate version exactly. nixpkgs (as of nixos-26.05) has `wasm-bindgen-cli_0_2_122` and
  `_0_2_126` but not 125.
- **Tailwind is v3** (`web/src/tailwind.css` uses `@tailwind base;`), so `tailwindcss_3`,
  not the default v4 `tailwindcss`.
- **Upstream tags are stale** — the newest tag is `v0.6.0` while `Cargo.toml` says 0.9.0.
  Pin a commit, not a tag.
- `rust-api` pulls in `aws-lc-sys` (via `jsonwebtoken`'s `aws_lc_rs` feature) and
  `openssl-sys`, so it needs `cmake`, `pkg-config` and `openssl` at build time.
- The OIDC callback the API registers is `{base_url}/api/auth/callback`
  (`rust-api/src/handlers/auth.rs:1308`).
- `SERVER_URL` (falling back to `HOSTNAME`) is what generates absolute URLs in RSS feeds.
  Upstream has a long comment in `startup.sh` about container runtimes clobbering
  `HOSTNAME`; setting `SERVER_URL` directly avoids that entirely.

## Decisions

1. **Host: `pizza`.** x86_64 so no cross-compilation of a Rust + wasm + Go stack; it
   already runs PostgreSQL 17, the Caddy/Authelia IAP, and has the `//norte/media` CIFS
   mount. `norte` was the alternative (it has the bulk storage) but it's an aarch64 Pi 5
   and the database and IAP live on `pizza` anyway.
1. **Auth: Authelia OIDC**, i.e. `bjackman.iap.services.pinepods.oidc.enable = true`,
   modelled on `nixos_modules/jellyfin.nix`. The default `forward_auth` used by
   miniflux/bitmagnet/silverbullet would break `/rss/…` feeds and gpodder sync, since
   external podcast clients can't do Authelia's browser login flow.
1. **Storage: `/mnt/nas-media/pinepods/`** for downloads and backups, like transmission.
   Local `/var/lib/pinepods` for `local-media` and `certs`.
1. **Native packaging, not `virtualisation.oci-containers`.** More work, but consistent
   with how everything else in this repo is run.
1. **Satisfy the hardcoded FHS paths with systemd bind mounts, not `substituteInPlace`.**
   There are ~30 occurrences across a handful of prefixes; patching them would be brittle
   across upstream updates, and the DB stores absolute download paths.

## Design

### Packaging: `packages/pinepods/default.nix`

New flake input, pinned to a commit, exactly like the existing `tvheadend` input:

```nix
pinepods = { url = "github:madeofpendletonwool/PinePods"; flake = false; };
```

Overlay entry in `flake.nix` alongside `tvheadend`:

```nix
pinepods = final.callPackage ./packages/pinepods { src = inputs.pinepods; };
```

The package builds four derivations and `symlinkJoin`s them, with `passthru` so the NixOS
module can reach the web dist directly. The date-plus-rev version trick from
`packages/tvheadend/default.nix` applies since there's no usable tag.

**`web`** — `rustPlatform.buildRustPackage`, `sourceRoot = "${src.name}/web"`,
`cargoLock.lockFile = "${src}/web/Cargo.lock"` (so no `cargoHash` to maintain). Follow the
nixpkgs trunk-offline pattern in `<nixpkgs>/pkgs/by-name/st/stalwart/webadmin.nix`, which
is the proof that this works in the sandbox:

- `nativeBuildInputs = [ trunk tailwindcss_3 binaryen wasm-bindgen-cli_0_2_125 ]`
- `buildPhase = "trunk build --offline --frozen --release --features server_build"`
- `env.RUSTFLAGS = "--cfg=web_sys_unstable_apis --cfg getrandom_backend=\"wasm_js\""`
- Install `dist/` to `$out`, then additionally copy `web/src/translations` to
  `$out/static/translations`. Trunk only copies `web/static`; the Dockerfile adds the
  translations in a separate `COPY`, and the API reads them from
  `/var/www/html/static/translations`.

`--offline` is what makes trunk use `wasm-bindgen`, `wasm-opt` and `tailwindcss` from
`$PATH` instead of downloading them. For the 0.2.125 CLI, copy
`<nixpkgs>/pkgs/by-name/wa/wasm-bindgen-cli_0_2_126/package.nix` (it's a five-line call to
the `buildWasmBindgenCli` helper) and change the version and its two hashes.

**`api`** — `rustPlatform.buildRustPackage`, `sourceRoot = "${src.name}/rust-api"`,
`cargoLock.lockFile`. `nativeBuildInputs = [ pkg-config cmake makeWrapper ]`,
`buildInputs = [ openssl ]`. `postInstall` wraps the binary with `yt-dlp`, `ffmpeg` and
`postgresql` on `PATH`, the same `wrapProgram --prefix PATH` shape as the tvheadend
package.

**`gpodder`** — `buildGoModule`, `sourceRoot = "${src.name}/gpodder-api"`,
`subPackages = [ "cmd/server" ]`, installed as `pinepods-gpodder-api`.

**`db-setup`** — skip PyInstaller entirely. A `python3.withPackages` env plus a wrapper
that sets `PYTHONPATH` to a store dir holding `database_functions/` and runs
`startup/setup_database_new.py`.

**`root`** — trivial derivation containing just `current_version`.

### NixOS module: `nixos_modules/pinepods.nix`

Imports `./ports.nix ./iap.nix ./postgres.nix ./impermanence.nix`, following the shape of
`nixos_modules/miniflux.nix` and `bitmagnet.nix`. Imported from
`nixos_modules/pizza/default.nix`.

**Ports.** `bjackman.ports.pinepods = { }` for the nginx/IAP port, and
`bjackman.ports.pinepods-valkey = { }` for Valkey. Note that adding names to
`bjackman.ports` shifts the 9000+ allocations of alphabetically-later services
(silverbullet, transmission) — harmless because everything is addressed by subdomain, but
it does mean their listen ports change on the same deploy.

**IAP + OIDC.**

```nix
bjackman.iap.services.pinepods = {
  port = config.bjackman.ports.pinepods.port;
  oidc = { enable = true; inherit autheliaConfig; };
};
```

`autheliaConfig` copies the shape from `nixos_modules/jellyfin.nix` (top of file): a fresh
`client_id`, `client_secret` referencing the *hashed* secret through the
`{{- fileContent "…" | trim }}` template, `require_pkce`, and
`redirect_uris = [ "${config.bjackman.iap.services.pinepods.url}/api/auth/callback" ]`.

**Database.** PostgreSQL on `pizza` already listens on localhost TCP — the nixpkgs module
sets `listen_addresses = "localhost"` unless `enableTCPIP`, and the default `pg_hba` has
`host all all 127.0.0.1/32 md5`. So no postgres config change is needed beyond:

```nix
services.postgresql = {
  ensureDatabases = [ "pinepods" ];
  ensureUsers = [ { name = "pinepods"; ensureDBOwnership = true; } ];
};
```

`ensureUsers` can't set a password, so a oneshot `pinepods-db-password.service` runs as
`postgres` after `postgresql.service` and does
`psql -v pw="$(cat $SECRET)" -c "ALTER ROLE pinepods PASSWORD :'pw'"` — psql's `:'var'`
interpolation handles the quoting.

**Valkey.** There's no `services.valkey` module in this nixpkgs, so use the redis module
with the valkey package:

```nix
services.redis.servers.pinepods = {
  enable = true;
  package = pkgs.valkey;
  bind = "127.0.0.1";
  # Named redis servers default to port 0 (unix socket only), and the API is TCP-only.
  port = config.bjackman.ports.pinepods-valkey.port;
};
```

**FHS paths.** `systemd.tmpfiles` creates empty mountpoints (`/opt/pinepods`, `/pinepods`,
`/var/www/html`) and the units bind the real content in inside their mount namespace:

```nix
BindPaths = [
  "/mnt/nas-media/pinepods/downloads:/opt/pinepods/downloads"
  "/mnt/nas-media/pinepods/backups:/opt/pinepods/backups"
  "/var/lib/pinepods/local-media:/opt/pinepods/local-media"
  "/var/lib/pinepods/certs:/opt/pinepods/certs"
];
BindReadOnlyPaths = [
  "${pkgs.bjackman.pinepods.web}:/var/www/html"
  "${pkgs.bjackman.pinepods.root}:/pinepods"
];
```

Creating the mountpoints explicitly rather than relying on systemd to create bind-mount
destinations avoids the interaction where `ProtectSystem=strict` makes the parent
read-only in the namespace.

**Units.** Three, replacing upstream's horust supervision:

1. `pinepods-api.service` — `ExecStartPre` runs `pinepods-db-setup` (it's idempotent by
   design and upstream runs it on every start, so folding it in beats a separate unit),
   `ExecStart` runs `pinepods-api`. `User`/`Group` `pinepods`,
   `SupplementaryGroups = [ "nas-media" ]`, `StateDirectory = "pinepods"`,
   `Restart = "always"`. Ordered after postgresql, `redis-pinepods.service` and
   `pinepods-db-password.service`, with
   `unitConfig.RequiresMountsFor = [ "/mnt/nas-media/pinepods" ]` and the same
   restart-tolerance treatment transmission gets in `nixos_modules/pizza/default.nix` for
   when `norte` is slow to come up after a reboot.
1. `pinepods-gpodder-api.service` — same user, `SERVER_PORT=8042` plus the `DB_*` vars.
1. nginx (below).

Non-secret environment: `DB_TYPE=postgresql`, `DB_HOST=127.0.0.1`, `DB_PORT`,
`DB_USER=pinepods`, `DB_NAME=pinepods`, `VALKEY_HOST`/`VALKEY_PORT`, `SEARCH_API_URL` and
`PEOPLE_API_URL` (both mandatory — default to the public
`https://search.pinepods.online/api/search` and `https://people.pinepods.online`),
`SERVER_URL = config.bjackman.iap.services.pinepods.url`, `TZ`,
`USERNAME`/`EMAIL`/`FULLNAME` for the initial admin, and the `OIDC_*` block pointing at
`config.bjackman.iap.autheliaUrl`.

**nginx.** `startup/nginx.conf` translated into a `services.nginx.virtualHosts.pinepods`
listening on `127.0.0.1:${ports.pinepods.port}` with `root = pkgs.bjackman.pinepods.web`.
Caddy reverse-proxies to `localhost:<port>` for same-host services, so binding to loopback
is fine. Locations:

- `/` → `try_files $uri $uri/ /index.html`
- `/api`, and `/api/gpodder` with 30-minute timeouts → `127.0.0.1:8032`
- `/rss/` → `127.0.0.1:8032`, with the `^/rss/(\d+)(?:/(\d+))?$` → `/api/feed/$1$2`
  rewrite and `proxy_set_header Api-Key $arg_api_key`
- `/ws/api/data/` and `/ws/api/tasks/` → `127.0.0.1:8032` with `proxyWebsockets = true`
- `~ ^/(api/2|auth|subscriptions|devices|updates|episodes|settings|lists|favorites|sync-devices|search|suggestions|toplist|tag|tags|data)/`
  → `127.0.0.1:8042`
- `client_max_body_size 0`, for backup upload/restore
- Upstream's wildcard `Access-Control-Allow-Origin *` can be dropped: the UI is
  same-origin and the whole thing sits behind the IAP.

This would be the first nginx in the repo. It doesn't clash with the IAP's Caddy since it
only binds the one loopback port.

**Impermanence.** `/var/lib/pinepods` added to
`bjackman.impermanence.extraPersistence.directories`, like the jellyfin and postgres
entries.

### Secrets

Four new agenix secrets, registered in `secrets/secrets.nix` with `all-personal`:

- `secrets/pinepods-db-password.age`
- `secrets/pinepods-admin-password.age` — the initial admin account password
- `secrets/authelia/pinepods-client-secret.age` and `…-client-secret-hash.age` —
  generated with
  `nix run nixpkgs#authelia -- crypto hash generate pbkdf2 --random --random.length 72`

Delivered to the service with the existing helper, the same way `iap.nix` does it for
Caddy:

```nix
bjackman.derived-secrets.envFiles.pinepods.vars = {
  DB_PASSWORD = config.age.secrets.pinepods-db-password.path;
  PASSWORD = config.age.secrets.pinepods-admin-password.path;
  OIDC_CLIENT_SECRET = config.age.secrets.authelia-pinepods-client-secret.path;
};
# derived-secrets.envFiles doesn't expose ownership, so set it on the underlying file.
age-template.files."pinepods.env".owner = "pinepods";
```

referenced from `serviceConfig.EnvironmentFile`.

## Risks

- **The trunk build is the risky part.** The stalwart-webadmin package proves
  `trunk build --offline` works under Nix, but the `wasm-bindgen-cli` 0.2.125 hashes and
  any `--frozen` friction only shake out in a real build.
- `aws-lc-sys` sometimes wants `libclang` in addition to `cmake`; add
  `rustPlatform.bindgenHook` if it complains.
- Bind-mounting a subdirectory of the CIFS automount into a service namespace is the same
  shape as transmission's sandbox, which has historically needed the `RequiresMountsFor`
  plus restart-retry treatment.
- Three separate upstream build systems with no upstream Nix support means version bumps
  will occasionally need hash updates in three places.

## Verification plan

1. `nix build .#pinepods`, and each sub-derivation individually first
   (`nix build .#pinepods.web` etc.) since the trunk build is the likely failure.
1. `nix build .#nixosConfigurations.pizza.config.system.build.toplevel` to confirm the
   module evaluates and builds.
1. After deploying, on `pizza`:
   - `systemctl status pinepods-api pinepods-gpodder-api redis-pinepods nginx`
   - `journalctl -u pinepods-api` should show migrations running and
     `Server listening on 0.0.0.0:8032`
   - `curl -fsS http://localhost:8032/api/health` — upstream's own healthcheck
   - `curl -fsS http://localhost:<ports.pinepods.port>/` returns the UI's `index.html`
   - `sudo -u postgres psql -d pinepods -c '\dt'` shows the schema
1. Browse to `https://pinepods.home.yawn.io`, log in via SSO, add a podcast and download
   an episode — that exercises the API, Valkey, the OIDC round trip, `yt-dlp`/`ffmpeg` and
   the NAS bind mount in one go.
