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

## TODO

- [x] Update Zed
- [x] Set up Zed alias for NixOS
- [x] Move remaining Chungito configuration into Home Manager as appropriate
- [x] Split up NixOS config into modules?
- [x] Make Fish default shell
- [x] Explore some FREAKY TILING WINDOW MANAGER BULLSHIT. OK actually just use
      Sway because Hyprland isn't really usable on Debian.
  - [x] Make waybar show workspaces
  - [x] Figure out workspace workflow for desktop:
        - super+b/n/m to switch to browser/terminal/editor workspaces
        - super+shift+b/n/m to move a window to the corresponding workspace
        - super+shift+h/l to move workspaces left and right between monitors
  - [x] Ensure bluetooth / sound / NetworkManager stuff is all usable
  - [ ] Figure out if I need an XDG portal and set one up.
  - [x] Make Chrome login work
  - [x] Make it derk mode
  - [x] Get a status bar working.
    - [ ] Set up battery icon if on laptop
    - [x] Make power control work
    - [x] Make it look nice
  - [x] Get a launcher working
  - [ ] Document it for myself
  - [ ] Figure out how to dynamically create workspaces
  - [ ] Figure out how to dynamically enable/disable third monitor
  - [ ] Figure out an "overview" mechanism like Gnome has. I tried this:
        https://code.hyprland.org/hyprwm/hyprland-plugins/src/branch/main/hyprexpo
        which is an official plugin that's supposed to this but I just got an
        error saying "hyrexpo:expo" wasn't valid, I guess I didn't install it
        properly.
  - [x] Set up a lock screen
  - [x] Make notifications work
  - [x] Make screensharing work
    - [ ] In Firefox
    - [ ] In Chrome
  - [x] Make Spotify work
  - [x] Make hyperlinks work in terminal
  - [x] Make it look like windows 98
  - [x] Make volume/backlight control buttons work.
- [x] Figure out impermanence for Chungito
- [ ] Document how all the parts of this repo fit together
- [ ] Figure out a nice way to CONSUME MEDIA potentially involving CRIME
- [ ] Figure out Non-NixOS:
  - [ ] Hyprlock
      - Basically do the non-NixOS equivalent of `security.pam.services.hyprlock = {};`
  - [ ] Screen sharing
- [ ] Switch back to VSCode
  - [x] Set up sway workspace thingy
  - [x] Disable annoying AI shit
  - [ ] Install extensions with impermanence:
    - [ ] Markdown All in One
    - [ ] Vim
    - [ ] Trailing Spaces
  - [ ] Refactor symlink magic?

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
That's where you configure which keys can decrypt it. Then run `agenix -e
<name>.age`. Then to make it get decrypted at runtime, add it to `age.secrets`
in the home-manager/NixOS config.

To add a recipient key for a secret, update `secrets.nix` to include it in that
secret's `publicKeys`setting, then run `agenix -r` from the `secrets/` dir.
Note that this requires decrypting the keys, which your current user might not
have the ability to do if the only recipients are host keys. In that case, use
the `-i` flag to point agenix at a private key that can decrypt it, e.g. `sudo
agenix -r -i /etc/ssh/ssh_host_ed25519_key`.

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
