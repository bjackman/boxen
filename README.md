# My boxen

```
 _________________________________________
/ THIS IS MY PILE OF NIXOS AND HOME       \
| MANAGER MODULES AND SHIT                 |
|                                         |
| THERE ARE MANY LIKE IT BUT THIS ONE     |
| IS MINE                                 |
|                                         |
| MY NIX CODE IS MY BEST FRIEND           |
|                                         |
\ IT IS  MY LIFE                          /
 -----------------------------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
```

## Flake structure

This flake uses `flake-parts`. `flake-parts`' documentation is really reference
only, there's not much conceptual introduction. Here's a snapshot of the key
parts of my current understanding:

### Module systems

`flake-parts` creates a third module system, so we have:

1. `flake_modules/` which define the flake outputs.

   1b. There is also a _nested_ module system within this namely the `perSystem`
   modules, described below.

1. `nixos_modules/` which are used to construct NixOS configs. But of course the
   NixOS configs are instantiated by flake modules, and there are some NixOS
   modules directly inline in flake modules.

1. `hm_modules/` which are used to construct Home Manager configs, which again
   are instantiated by, and may be inline in, flake modules. But Home Manager
   modules are _also_ constructed by NixOS modules.

The different module systems interact in two main ways:

- Flake modules instantiate nixpkgs, and the nixpkgs instantiation is passed to
  the HM config constructor. AI claims that this nixpkgs instantiation isn't
  actually used directly but rather HM reconstructs its own nixpkgs by
  inspection. NixOS configs _can_ be directly passed an existing nixpkgs
  instantiation but in this config I have tried to avoid that, instead NixOS
  configs just reuse overlays and construct their own `pkgs` - this helps avoid
  flake-level code having to deal _too much_ with instantiating nixpkgs correctly
  for different configs, older versions had bugs in this area.

- `specialArgs` - this is the most important way. When flake modules instantiate
  NixOS/HM configurations, they set additional arguments that get passed to each
  module. In this flake that is used to:

  - Pass extra nixpkgs instantiations in, namely we add `pkgsUnstable` so that
    we can install the latest version of a package even if the rest of the system
    is on the stable release.

  - Make modules "aware" that they are in a flake, that is we pass in `inputs`
    and allow modules to refer to them directly.

    This is a bit of a confusing corner of the programming style in here and
    something I've ummed and ahh'd about a bit, something that will likely be
    changed later. Suppose you want to refer, in a module, to package that is not
    in upstream nixpkgs. You could:

    1. Pass it in directly via `specialArgs`, this is nice and explicit but it
       would get pretty messy when instantiating modules. Note in this style
       `specialArgs` is a "bottleneck" that everybody's args have to go through.
       This is more appealing in the context of instantiating _packages_ with
       non-nixpkgs dependencies (since each package can have its own extra
       arguments that you add to the `callPackage` invocation) but for modules I
       think it would be a mess.

    1. Add it to an overlay which you apply to nixpkgs before instantiating the
       module, then have the module just refer to it via `pkgs`. This is concise
       and keeps your module "ignorant" of the overall system that is
       instantiating it.

    1. Add the whole of the flake's `inputs` to `specialArgs`. Referring to
       `inputs` in the module makes it nice and clear in module code that you
       are referring to something "custom", but it also means your module is
       coupled to the fact that it's in a flake.

    In this code we go for a combination of 2 and 3: For flake modules, option 3
    has no real downside since they are inherently coupled to the flake (they
    _are_ the flake). For NixOS and HM modules we try to use option 2 for
    packages, but then we end up using option 3 anyway e.g. for module imports.

    A particular foible of option 3 is that for flake modules, we pass `inputs`
    as its own `specialArgs` but for NixOS/HM modules we splat the inputs into
    their own arguments and refer to them directly. However then we _ALSO_ still
    pass in the whole `inputs` into NixOS modules, since that's needed in order
    to forward them wholesale to instantiated HM modules. Perhaps a reason for
    preferring the individual-arg style in the past was that it doesn't couple
    the modules to a flake quite so explicitly (you could still pass the inputs
    individuall via `specialArgs` i.e. option 1 above). But now that we are
    forced to have the `inputs` arg anyway we should probably just use that
    everywhere.

### How `flake-parts` works

Aside from modularising the flake, `flake-parts` also divides the world into
"system-agnostic" stuff (defined directly in the `flake` option) and `perSystem`
stuff. System-agnostic stuff doesn't get an instantiated nixpkgs (you don't get
a `pkgs` module argument at all).

`perSystem` is a flake option that takes a module as its value. This module
_does_ get a `pkgs` argument. So, you define packages inside the `perSystem`. In
this flake, the way the nixpkgs instantiations actually happen is configured in
`flake_modules/nixpkgs.nix`.

Then, in the system-agnostic parts you can still "reach" into the `perSystem`
parts with `withSystem`(and some related functions too).

## HOWTOs

### Adding a new user for dä homelab

`nix run .#add-user -- <username>`

### Deploying dashboards

Either just deploy (slow) or be a legend and deploy directly:

```sh
percli login https://perses.home.yawn.io
nix build .#nixosConfigurations.pizza.config.bjackman.perses.resourceConfigs && percli apply -d result/
```

## Installing

How I installed `pizza`:

- Check out `813e8d1ec22e`

- `nix build .#nixosConfigurations.pizza.config.system.build.isoImage`. This
  builds an installer image.

- Boot the installer on the machine, plug it into the network.

- Can now SSH to the machine on the LAN.

- Modify the configuration like in `18ab3a3`, that is at least:

  - Remove the installer module and enable a bootloader
  - Add a Disko configuration

- Run `nixos-anywhere` e.g.:

  ```sh
  nix run github:nix-community/nixos-anywhere -- \
            --flake .#pizza --generate-hardware-config nixos-generate-config \
          ./nixos_modules/pizza/hardware-configuration.nix \
          --target-host pizza.fritz.box
  ```

Note this process won't work if secrets are needed for the machine to work (e.g.
if there is a login password that is managed by this repo). You need to
bootstrap the configuration so that the system can generate host keys and you
can rekey secrets to allow it to access them.

## TODOs

- [x] Fix borked machines
- [x] Unbrick deadlocked Norte
- [x] Unbrick remote pizza access
- [x] Figure out where ZFS media went on norte
- [ ] Get watchdogs working (test with `ls /mnt/nas/.zfs/snapshots/*/media`)
- [x] Investigate if `sops-nix` is better than `agenix`. Main goal is we need to
  be able to generate stuff like configs containing secrets, on the host.
  (Conclusion: agenix-template and also my own custom stuff, see
  `derived-secrets.nix`)
- [x] Get Authelia running
- [x] Get FileBrowser running
- [x] Get FileBrowser accepting auth from Athelia
- [x] Make creating Authelia users more practical
- [x] Make creating FileBrowser users more practical
- [x] Make FileBrowser able to access NAS data (read/write)
- [x] Set up some monitoring. In particular it would be nice to know about
  watchdog resets.
- [x] Figure out how to integrate values from Nix into the TF configuration
- [ ] Figure out how to run OpenTofu as part of the Nix deployment (maybe run it
  on Pizza?)
- [x] Delete NFS server code, pretty sure I'm a Samba guy now.
- [x] Currently I believe Jellyfin auth is only working because I have set up
  "known proxies" and "published web URLs" via the UI. Check if that's true and,
  if so, fix it. (It was only the known proxies)
- [ ] Jellyfin KnownProxies is configured via my forked Jellyfin with an AI slop
  patch to add networking configuration.
- [ ] See if it's possible to virtualise these systems so that I can vibe-code
  in this repo.
- [ ] Run Woodpecker CI (or similar) in homelab.
- [ ] Set up cloud archive backups
- [ ] Set up SeaweedFS (or similar) in homelab.
- [ ] Make slopbox have a persistent up-to-date setup
- [ ] Give slopbox its own Git identity
- [ ] Improve "slopbox mode" agent prompt (perhaps it would be better as a
  "skill").

## Inspecting the config

NixOS options are under `.#nixosConfigurations.<config>.config`. So for example:

```sh
# Show security.pam.loginLimits option
nix eval .#nixosConfigurations.chungito.config.security.pam.loginLimits
```

For NixOS hosts, Home Manager options are under
`.#nixosConfigurations.<config>.config.home-manager.users.<user>` So for example:

```sh
# Show programs.waybar.enable option
nix eval .#nixosConfigurations.chungito.config.home-manager.users.brendan.programs.waybar.enable
```

For hosts using Home Manager standalone, they are under
`.#homeConfigurations.<config>`. So for example:

```sh
nix eval '.#homeConfigurations.brendan.config.programs.vim.defaultEditor'
```

## Secrets

Secrets are stored using [agenix](https://github.com/ryantm/agenix). At runtime
they get decrypted and dumped into a tmpfs as plaintext (lol).

To add a secret, run `nix develop` to get the `agenix` CLI, then go into
`secrets/` and add it to `secrets.nix` following the existing pattern in there.
That's where you configure which keys can decrypt it. Then run `agenix -e <name>.age`.
Then to make it get decrypted at runtime, add it to `age.secrets`
in the home-manager/NixOS config.

To add a recipient key for a secret, update `secrets.nix` to include it in that
secret's `publicKeys`setting, then run `agenix -r` from the `secrets/` dir.
Note that this requires decrypting the keys, which your current user might not
have the ability to do if the only recipients are host keys. In that case, use
the `-i` flag to point agenix at a private key that can decrypt it, e.g.
`sudo agenix -r -i /etc/ssh/ssh_host_ed25519_key`.

## Diffing configs

You can use [`nix-diff`](https://github.com/Gabriella439/nix-diff) (with
`NIX_REMOTE` unset to work around a
[bug](https://github.com/Gabriella439/nix-diff/issues/98)) to compare the result:

```bash
home-manager build
mv result result.old

# ... Make changes

home-manager build
NIX_REMOTE= nix-diff result result.old
```

## ESPHome

I have an Apollo Air 1 on my LAN. It comes pre-flashed and I configured it via
its captive portal hotspot to connect to my WiFi. However I wanted to add
Prometheus metric support so I have a customized build that imports the upstream
config from the supplier.

First you need to populate `esphome/secrets.yaml` with the `wifi_ssid` and
`wifi_password` properties.

The NixOS ESPHome packaging seems to be broken. Instead set up Podman with
Docker compat mode (https://wiki.nixos.org/wiki/Podman) then do this from the
`esphome` dir:

```sh
podman  run --rm -v "$PWD":/config -it ghcr.io/esphome/esphome  run apollo-air.yaml --device 192.168.178.109
```

That will compile and install the updated firmware and then show you the logs -
when you're done you can just terminate this process and the firmware will keep
running.

## Developing the Homepage

The homepage at `https://home.yawn.io` is a simple static site built with `pandoc` from Markdown.

### Building

To build the homepage package:

```sh
nix build .#homepage
```

The output will be in `./result`.

### Local Development

To work on the homepage locally with a dev shell:

```sh
nix develop .#homepage
cd packages/homepage
```

Inside the shell, you can preview changes:

```sh
# Build the HTML
pandoc index.md --standalone --css assets/style.css -o index.html

# Start a local server
python3 -m http.server
```

Then open `http://localhost:8000` in your browser.

## Terraform

For stuff that isn't really designed to be configured declaratively, I
eventually realised that the ideal model is Terraform. This is integrated into
the rest of the config but it doesn't get deployed by deploy-rs.

Just run `nix run .#deploy-tf-*` to deploy it. Note Terraform relies on a
statefile which I haven't backed up anywhere right now.

## Mail

### How it works

There is a system for working with LKML in here. It's defined in
`modules/lkml.nix` but it's unfortunately coupled with the
`accounts.email.accounts` definition in an awkward way (see TODOs in the code).

It works like this:

- A command called `get-lkml` takes care of fetching mail. It's also run via a
  systemd service.

  - LKML mail is fetched from Lore using
    [`lei`](https://public-inbox.org/lei.html). This goes into `~/Maildir/lore`.

  - Separately from this, mail is fetched from my actual mailbox via IMAP, this
    goes into `~/Maildir/linuxdev`.

  - `notmuch` then indexes the whole of `~/Maildir`. It should detect duplicates
    for messages that appear in both lore and the IMAP mailbox.

- There is a script packaged `notmuch-propagate-mute` which provides a muting
  mechanism (which AFAICT exists in no mail clients for some reason) for keeping
  LKML volume manageable. This works based on `notmuch` tags.

- `aerc` is used as the actual mail client. A configuration is provided that is
  coupled with the tagging mechanism used by `notmuch-propagate-mute`:

  - There's a key binding for applying the tag that controls the muting

  - The view of "mailboxes" i.e. the "query map" takes into account the tag
    that is output by the muting script.

### Using it

The page you open on is called the "message list". The navbar to the left shows
you "folders" in Aerc terminology. Under this config, "folders" are actually
defined as notmuch queries in the `query-map`.

All the operations below are defined in the `binds.conf` as commands, check in
there to see the name of the command corresponding to the keys. You can also use
`?` to see the current bindings.

- `j`/`k` scrolls in the message list itself
- `J`/`K` scrolls between folders
- `v` "marks" the highlighted message. `ctrl-v` marks the whole thread. `V`
  unmarks the whole thread.
- `a` archives the selected (marked, or currently highlighted) messages. This
  just hides those specific messages using a notmuch tag.
- `m` mutes the selected messages, this applies the `notmuch-propagate-mute`
  magic.

Press enter on a message to open it in the "message viewer". You'll note this
opens a new "tab" within Aerc.

- `ctrl-p`/`ctrl-n` changes between tabs.

In the message viewer:

- The main view is a pager, running in Aerc's internal terminal emulator. The
  headers are at the top, I'm not sure how to navigate into those.
- `J`/`K` flips between messages
- `rq` is reply-all.
- `H` toggles view of the headers in the pager. This is useful because I don't
  know how to navigate the header view at the top.

When you start composing a message you are in the "compose" view. You're in an
$EDITOR inside Aerc's terminal emulator. So most of your keypresses go to the
editor, but:

- `ctrl-PageUp/PageDown` switches to other Aerc tabs
- `ctrl-j/k` switches focus to the headers at the top of the window. The editor
  is like another field, you can scroll down to it to get back to editing.
- `ctrl-x` gives you an Aerc command prompt, this is writen in the bindings
  config with `$ex` - I don't understand this.

### Syncing tags between devices

The config in this repo should automatically cause all the relevant mails to be
downloaded from remote severs. The important "state" is mostly in notmuch tags
though. These are synced between devices, and thereby also backed up, using
[`notmuch git`](https://notmuchmail.org/doc/latest/man1/notmuch-git.html),
which stores tags as empty files in a git repository and thereby gets sane
bidirectional merge semantics for free (raw `notmuch dump`/`restore` is
last-writer-wins, so concurrent tag changes on two devices would clobber each
other).

- The hub is the `brendan/lkml-tags` repo on the Forgejo instance, accessed
  over SSH via the tailnet. The remote URL is derived from the Forgejo server's
  own config via the `homelab` plumbing - see the `lkml.tagsRepoUrl` option and
  the comment where it's set for why it can't use the iap fqdn.

- A `sync-lkml-tags` script, run every 15 minutes by a systemd user timer, does
  commit → fetch → merge → push against a local repo at notmuch-git's default
  location, `~/.local/share/notmuch/default/git`.

- The first run on a device is a special case, and there are two different
  ones. If the remote is still empty, it just creates the repo. If another
  device has already synced, it instead clones the remote and _unions_ the two
  tag sets (via `notmuch dump`/`restore --accumulate`): there's no common
  ancestor yet, so neither side is "newer", and taking either one wholesale
  would throw away the other device's tags. Both cases force past notmuch-git's
  `git.safe_fraction` check, since a device's first commit "changes" every
  message's tags. Afterwards the check stays active for normal operation.

- Devices don't need identical maildirs, but this depends on a detail worth
  knowing about. notmuch-git has to distinguish "this tag is in git but its
  message isn't in my database" from "this tag was deleted here", and only
  commit the latter. It asks the database via notmuch2, and when it can't
  import that it silently falls back to a check that answers "known" for every
  message - so it commits deletions for everything the other device has and
  this one doesn't. nixpkgs doesn't put notmuch2 on notmuch-git's path, so
  `sync-lkml-tags` sets PYTHONPATH itself. Don't remove that.

  Even with notmuch2 there's a residual case: a message this device knows only
  as a ghost (referenced by a thread it has, but not itself present) counts as
  known, so its tags do get committed as deletions. That's rare enough to live
  with - it was ~30 messages out of ~6700 when the two devices first met.

- Failure is mostly benign: if a device is offline the fetch/push just fails
  and gets retried later. A push rejected because the other device got there
  first is fetched, merged and retried within the same run. A hand-run sync
  takes a `flock` so it can't collide with the timer, which matters because the
  first sync on a device takes minutes.

  The exception is a failed `notmuch git merge`, which is why the script leaves
  a `sync-broken` marker in the repo and refuses to run until it's removed.
  `merge` does the git merge _before_ loading the result into notmuch, so if
  the load aborts (most likely `safe_fraction`, after a big batch of tagging on
  the other device) the repo is left ahead of the database - and the next run's
  `commit` would take the stale database as truth and silently revert the other
  device's work. Resolve by hand with `notmuch git status` and, if the diff
  really is legitimate, `notmuch git checkout --force`.

The Forgejo repo must be created by hand, as a completely empty repo (no README
etc). Whichever device syncs first populates it.

If a device's local repo ever gets into a state that can't be reconciled (e.g.
unrelated histories), it's just a cache of the database plus the remote - delete
it and re-run `sync-lkml-tags` to re-join from scratch:

```sh
rm -rf ~/.local/share/notmuch/default/git && sync-lkml-tags
```
