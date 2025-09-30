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
- [ ] Explore some FREAKY TILING WINDOW MANAGER BULLSHIT. OK actually just use
      Sway because Hyprland isn't really usable on Debian.
  - [x] Make waybar show workspaces
  - [ ] Figure out workspace workflow for desktop:
        - super+b/n/m to switch to browser/terminal/editor workspaces
        - super+shift+b/n/m to move a window to the corresponding workspace
        - super+shift+h/l to move workspaces left and right between monitors
  - [ ] Ensure bluetooth / sound / NetworkManager stuff is all usable
  - [ ] Figure out if I need an XDG portal and set one up.
  - [ ] Make Chrome login work
  - [ ] Make it derk mode
  - [ ] Get a status bar working.
    - [ ] Set up battery icon if on laptop
    - [ ] Make power control work
    - [ ] Make it look nice
  - [ ] Get a launcher working
  - [ ] Document it for myself
  - [ ] Figure out how to dynamically create workspaces
  - [ ] Figure out how to dynamically enable/disable third monitor
  - [ ] Figure out an "overview" mechanism like Gnome has. I tried this:
        https://code.hyprland.org/hyprwm/hyprland-plugins/src/branch/main/hyprexpo
        which is an official plugin that's supposed to this but I just got an
        error saying "hyrexpo:expo" wasn't valid, I guess I didn't install it
        properly.
  - [ ] Set up a lock screen
  - [ ] Make notifications work
    - I can get notifications via `notify-send` but Firefox won't send them via
      DBus.
  - [ ] Make screensharing work
    - [ ] In Firefox
    - [ ] In Chrome
  - [ ] Make Spotify work
  - [ ] Figure out if I really wanna start services from hyprland, see about
        using systemd properly.
  - [ ] Fix the cursor
  - [ ] Make hyperlinks work in terminal
  - [ ] Make it look like windows 98
  - [ ] Make volume/backlight control buttons work.
- [ ] Figure out impermanence for Chungito
- [ ] Document how all the parts of this repo fit together
- [ ] Figure out a nice way to CONSUME MEDIA potentially involving CRIME
- [ ] Figure out Non-NixOS:
  - [ ] Hyprlock
      - Basically do the non-NixOS equivalent of `security.pam.services.hyprlock = {};`
  - [ ] Screen sharing

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

## Secrets

Secrets are stored using [agenix](https://github.com/ryantm/agenix). At runtime
they get decrypted and dumped into a tmpfs as plaintext (lol).

To add a secret, run `nix develop` to get the `agenix` CLI, then go into
`secrets/` and add it to `secrets.nix` following the existing pattern in there.
That's where you configure which keys can decrypt it. Then run `agenix -e
<name>.age`. Then to make it get decrypted at runtime, add it to `age.secrets`
in the home-manager config.

To add a recipient key for a secret, update `secrets.nix` to include it in that
secret's `publicKeys`setting, then run `RULES=secrets/secrets.nix nix develop -c
agenix -r` from the root of the repo.

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

    - The view of "mailboxes" i.e. the "query map" takes into account the tag that is output by the muting script.
