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
- [ ] Currently I believe Jellyfin auth is only working because I have set up
  "known proxies" and "published web URLs" via the UI. Check if that's true and,
  if so, fix it.
- [ ] Clean up `specialArgs` (for both NixOS and Home Manager). I think I probably
  just want to pass `inputs` into the modules.
- [ ] See if it's possible to virtualise these systems so that I can vibe-code
  in this repo.
- [ ] Run Woodpecker CI (or similar) in homelab.
- [ ] Set up cloud archive backups
- [ ] Set up SeaweedFS (or similar) in homelab.
- [ ] Make slopbox have a persistent up-to-date setup
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
nix eval '.#homeConfigurations.jackmanb@jackmanb01.config.wayland.windowManager.sway.xwayland'
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
```

Inside the shell, you can preview changes:

```sh
# Build the HTML
pandoc packages/homepage/index.md --standalone --css packages/homepage/style.css -o index.html

# Start a local server
python3 -m http.server
```

Then open `http://localhost:8000` in your browser.

## Terraform

For stuff that isn't really designed to be configured declaratively, I
eventually realised that the ideal model is Terraform. This is integrated into
the rest of the config but it doesn't get deployed by deploy-rs.

Just run `nix run .#deploy-tf` to deploy it. Note Terraform relies on a
statefile which I haven't backed up anywhere right now.

## Mail

### How it works

There is a system for working with LKML in here. It's defined in
`modules/lkml.nix` but it's unfortunately coupled with the
`accounts.email.accounts` definition in an awkward way (see TODOs in the code).

It works like this:

- A command called `get-lkml` takes care of fetching mail. It's also run via a
  systemd service.

  - Email is fetched from Lore using [`lei`](https://public-inbox.org/lei.html).
    There is **no IMAP** or anything, this system works exclusively from mailing
    list archives. If someone emails you without CCing the list, you just have to
    reply via webmail or something.

  - It's then indexed using `notmuch`

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
