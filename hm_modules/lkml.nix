{
  config,
  pkgs,
  lib,
  ...
}:
{
  options.lkml = {
    enable = lib.mkEnableOption "lkml";
    # TODO: This is a bit crazy. Probably the solution to that is to drop the
    # usage of high-level aerc and notmuch configuration, and instead configure
    # them directly via home.files in here.
    accountRef = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of the account in accounts.email.accounts that LKML should be set
        up for. Note this will set up additional configuration for that account
        since it has program configurations that are coupled with it.
      '';
    };

    tagsRepoUrl = lib.mkOption {
      type = lib.types.str;
      description = ''
        Git remote holding the notmuch tag database, synced via notmuch-git.
        Must be writable non-interactively (e.g. over SSH).
      '';
    };

    extraAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Other emails that you use to interact with LKML.

        This can be used to see mail that was sent to other addresses than the
        ones that you are actually configuring for SMTP/git-send-email etc.
        (e.g. from previous jobs).

        NOTE: This assumes that the mails come from "you". Mails from this
        addresses are automatically marked as "read". This logic will need to be
        tweaked if you want to "subscribe" to other contributors.
      '';
    };
  };
  config = lib.mkIf config.lkml.enable (
    let
      cfg = config.lkml;
      account = config.accounts.email.accounts.${cfg.accountRef};
      allAddresses = [ account.address ] ++ cfg.extraAddresses;

      filter-dead-addresses = pkgs.writeShellApplication {
        name = "filter-dead-addresses";
        runtimeInputs = [ pkgs.bjackman.notmuch-get-dead-addresses ];
        text = ''
          # One address per line in, a header value out. Never fails and never
          # emits a trailing newline: aerc substitutes this into a header block
          # and falls back to the unfiltered stdin on a non-zero exit.
          exec awk '
            BEGIN {
              cmd = "notmuch-get-dead-addresses --cache"
              while ((cmd | getline line) > 0)
                if (line != "") dead[tolower(line)] = 1
              close(cmd)
            }
            $0 != "" {
              addr = $0
              if (match(addr, /<[^<>]*>$/))
                addr = substr(addr, RSTART + 1, RLENGTH - 2)
              if (tolower(addr) in dead) next
              out = out (n++ ? ", " : "") $0
            }
            END { printf "%s", out }
          '
        '';
      };
    in
    {
      programs.notmuch = {
        enable = true;
        extraConfig = {
          maildir.synchronize_flags = "true";
        };
        # If "I" wrote a mail, consider it as "read" from the start.
        hooks.postNew =
          let
            fromMatchers = map (addr: "from:${addr}") allAddresses;
            fromQuery = "(" + (lib.concatStringsSep " or " fromMatchers) + ")";
          in
          ''
            notmuch tag -unread "tag:unread and ${fromQuery}"
            ${pkgs.bjackman.notmuch-get-dead-addresses}/bin/notmuch-get-dead-addresses --refresh > /dev/null
          '';
      };

      programs.aerc = {
        enable = true;
        extraConfig = {
          # aerc is fussy about config permissions since you might put creds in
          # there. Nix doesn't support having the cautious permissions, but we won't
          # put creds in it (they would be leaked into the Nix store anyway).
          general.unsafe-accounts-conf = true;

          # Describes the format for each row in a mailbox view. This is a comma
          # separated list of column names with an optional align and width suffix. After
          # the column name, one of the '<' (left), ':' (center) or '>' (right) alignment
          # characters can be added (by default, left) followed by an optional width
          # specifier. The width is either an integer representing a fixed number of
          # characters, or a percentage between 1% and 99% representing a fraction of the
          # terminal width. It can also be one of the '*' (auto) or '=' (fit) special
          # width specifiers. Auto width columns will be equally attributed the remaining
          # terminal width. Fit width columns take the width of their contents. If no
          # width specifier is set, '*' is used by default.
          #
          # Default: flags:4,name<20%,subject,date>=
          ui = {
            index-columns = "addressed:1,flags:4,name<20%,subject<60%,date>,tags";

            # Show Notmuch tags in a column, excluding the ones that are already implied by
            # the context of the UI.
            column-tags = ''{{map .Labels (exclude "inbox" ) (exclude "read") (exclude "replied") | join " "}}'';
            # Show a single character 'A' if I'm personally addressed, otherwise or ' ' .
            # Works by joining together all the To and Cc emails into a single string and
            # then searching. Maybe dumb, whatever.
            column-addressed = lib.trim ''
              {{ if contains "${account.address}" (printf "%s%s" (.To | emails | join "") (.Cc | emails | join "")) }}A{{ else }} {{ end }}
            '';

            # Sort the thread siblings according to the sort criteria for the messages. If
            # sort-thread-siblings is false, the thread siblings will be sorted based on
            # the message UID in ascending order. This option is only applicable for
            # client-side threading with a backend that enables sorting. Note that there's
            # a performance impact when sorting is activated.
            #
            # Default: false
            sort-thread-siblings = true;

            #
            # Enable a threaded view of messages. If this is not supported by the backend
            # (IMAP server or notmuch), threads will be built by the client.
            #
            # Default: false
            threading-enabled = true;
          };
          # I don't know what this does really, but aerc couldn't open anything
          # until I set it.
          filters = {
            "text/plain" = "colorize";
            "text/calendar" = "calendar";
            "message/delivery-status" = "colorize";
            "message/rfc822" = "colorize";
            ".headers" = "colorize";
          };
          # Unsure why but if I don't set this explicitly opening messages does
          # nothing.
          viewer.pager = "less -Rc";
        };
      };

      # Note we'd prefer this to be two separate stanzas with the notmuch stuff
      # next to the programs.notmuch config and the aerc stuff next to
      # programs.aerc, but it seems the Nix language desn't support that for
      # "dynamic attributes" like this.
      accounts.email.accounts.${cfg.accountRef} = {
        notmuch.enable = true;

        aerc = {
          enable = true;
          extraAccounts =
            # This configures the "folders", i.e. the things in the side bar, by
            # mapping them to notmuch queries.
            let
              queryMap = pkgs.writeText "query-map.conf" ''
                Inbox=not tag:archived and not tag:thread-muted
                All=true
              '';
            in
            {
              source = "notmuch://${config.accounts.email.maildirBasePath}";
              # Needed for postponing messages:
              #  https://lists.sr.ht/~rjarry/aerc-discuss/%3CD931B2ZI6UH5.1L6FTH0TGJIQO@google.com%3E
              maildir-store = config.accounts.email.maildirBasePath;
              query-map = "${queryMap}";
              # Prevent HM from restricting the maildir store to this account's subdir,
              # which would cause aerc to override query-map folders with physical queries.
              maildir-account-path = "";
            };
        };
      };

      # The HM packaging for Aerc call the setting "extraBinds", but actually
      # if you set it then those are the _only_ keybindings you yet.
      # If you don't set it, then Aerc will produce an initial keybinding
      # setup on first run. Therefore we don't set it here and instead we just
      # have a config file checked in.
      home.file =
        let
          filter = "${filter-dead-addresses}/bin/filter-dead-addresses";
          # Reply prefills To/Cc from the message being replied to, and a
          # template's headers take precedence over the ones aerc computed, so
          # this is the place to drop the dead addresses.
          #
          # A header whose addresses were all dead is still emitted, empty:
          # otherwise aerc's unfiltered version would stand. aerc deletes empty
          # recipient headers before sending.
          filterRecipients = pkgs.writeText "aerc-filter-recipients" ''
            {{- if .To }}To: {{ exec "${filter}" (.To | persons | join "\n") }}
            {{ end -}}
            {{- if .Cc }}Cc: {{ exec "${filter}" (.Cc | persons | join "\n") }}
            {{ end -}}
          '';
          # quoted_reply serves :reply -q, new_message everything else,
          # including plain :reply. The latter is also used by :compose, where
          # To/Cc are empty and the headers above collapse to nothing.
          filteredTemplate =
            name:
            pkgs.runCommand "aerc-template-${name}" { } ''
              cat ${filterRecipients} \
                ${config.programs.aerc.package}/share/aerc/templates/${name} > $out
            '';
          templateNames = [
            "new_message"
            "quoted_reply"
          ];
        in
        {
          # The HM packaging for Aerc call the setting "extraBinds", but actually
          # if you set it then those are the _only_ keybindings you yet.
          # If you don't set it, then Aerc will produce an initial keybinding
          # setup on first run. Therefore we don't set it here and instead we just
          # have a config file checked in.
          "${config.xdg.configHome}/aerc/binds.conf" = {
            source = ../hm_files/lkml/config/aerc/binds.conf;
          };
        }
        // lib.listToAttrs (
          map (name: {
            name = "${config.xdg.configHome}/aerc/templates/${name}";
            value.source = filteredTemplate name;
          }) templateNames
        );

      home.packages =
        let
          notmuchPython = pkgs.python3.withPackages (ps: [ ps.notmuch2 ]);
          # Dumb wrapper so I don't have to code args into the binds.conf
          do-notmuch-propagate-mute = pkgs.writeShellApplication {
            name = "do-notmuch-propagate-mute";
            runtimeInputs = [ pkgs.bjackman.notmuch-propagate-mute ];
            # Don't want errexit/pipefail as we'll be hiding the SIGABRT below.
            bashOptions = [ "nounset" ];
            text = ''
              notmuch-propagate-mute --email ${account.address} --db-path ${config.accounts.email.maildirBasePath} "$@"
              # Due to garbage Python bindings, the script always gets SIGABRT.
              # Hide that from this script's exit code since this will
              # eventually be used in a systemd service and it's annoying if
              # that shows as failing.
              exit 0
            '';
          };
          copy-lore-url = pkgs.writeShellApplication {
            name = "copy-lore-url";
            runtimeInputs = [
              pkgs.wl-clipboard
              pkgs.libnotify
              # IGNORECASE below is a gawk extension.
              pkgs.gawk
            ];
            # Takes a message ID as an argument, or a message on stdin. The
            # latter is what aerc uses: command templates like {{.MessageId}}
            # resolve against the message list's selection even when the
            # command was run from a message viewer showing something else.
            text = ''
              if [ $# -gt 0 ]; then
                msgid=$1
              else
                msgid=$(awk 'BEGIN { IGNORECASE = 1 }
                  /^$/ { exit }
                  /^message-id:/ { sub(/^[^:]*:[ \t]*/, ""); print; exit }')
              fi
              msgid=''${msgid#<}
              msgid=''${msgid%>}
              if [ -z "$msgid" ]; then
                notify-send -t 5000 "No lore URL" "Message has no Message-ID"
                exit 1
              fi
              url="https://lore.kernel.org/all/$msgid/"
              printf '%s' "$url" | wl-copy
              notify-send -t 5000 "Copied lore URL" "$url"
            '';
          };
          sync-lkml-tags = pkgs.writeShellApplication {
            name = "sync-lkml-tags";
            runtimeInputs = [
              pkgs.notmuch
              pkgs.git
              pkgs.openssh
            ];
            text = ''
              url=${lib.escapeShellArg cfg.tagsRepoUrl}

              # notmuch-git asks the database whether it knows a message before
              # treating a tag that's in git but not in the database as deleted
              # rather than as belonging to a message this device simply doesn't
              # have. Without notmuch2 it falls back to a check that considers
              # every message known, and nixpkgs doesn't put notmuch2 on its
              # path, so it commits deletions for the other device's tags.
              export PYTHONPATH=${notmuchPython}/${notmuchPython.sitePackages}
              NOTMUCH_GIT_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/notmuch/''${NOTMUCH_PROFILE:-default}/git"
              export NOTMUCH_GIT_DIR
              repo="$NOTMUCH_GIT_DIR"
              broken="$repo/sync-broken"

              # Merge commits take git's default message. Otherwise a hand-run
              # sync opens an editor, and only the absence of a tty keeps the
              # timer's run from trying to do the same.
              export GIT_MERGE_AUTOEDIT=no
              # Fail rather than hang on a prompt when run from the timer.
              export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

              # The first sync on a device takes minutes, so a hand-run one and
              # the timer can otherwise end up in the same repo at once.
              mkdir -p "$(dirname "$repo")"
              exec 9>"$repo.lock"
              if ! flock -w 10 9; then
                echo "another sync is already running, skipping" >&2
                exit 0
              fi

              if [ -e "$broken" ]; then
                echo "A previous merge left notmuch out of sync with $repo." >&2
                echo "Resolve by hand (see 'notmuch git status'), then rm $broken" >&2
                exit 1
              fi

              if ! [ -e "$repo" ]; then
                if git ls-remote --heads "$url" master | grep -q master; then
                  # Joining a sync that's already running elsewhere. Union the
                  # two tag sets: the remote's history has no ancestor in common
                  # with this database, so neither side's state can be treated
                  # as the newer one. checkout alone would drop this machine's
                  # tags, commit alone would drop the other's.
                  notmuch git clone "$url"
                  local_tags=$(mktemp)
                  notmuch dump --output="$local_tags"
                  notmuch git checkout --force
                  notmuch restore --accumulate --input="$local_tags"
                  rm -f "$local_tags"
                else
                  notmuch git init
                  git -C "$repo" symbolic-ref HEAD refs/heads/master
                  git -C "$repo" remote add origin "$url"
                fi
                # The first commit on a machine "changes" every message's tags,
                # tripping notmuch-git's git.safe_fraction check.
                notmuch git commit --force
              else
                notmuch git commit
              fi

              git -C "$repo" remote set-url origin "$url"
              # notmuch-git subcommands default to @{upstream}, which the init
              # path above doesn't set up.
              git -C "$repo" config branch.master.remote origin
              git -C "$repo" config branch.master.merge refs/heads/master

              # merge does the git merge before loading the result into notmuch,
              # so an aborted checkout (e.g. safe_fraction, after a big batch of
              # tagging elsewhere) leaves the repo ahead of the database. Stop
              # rather than let the next run commit the stale database over the
              # top, silently reverting the other machine.
              merge() {
                # Absent when this device is the one creating the remote.
                git -C "$repo" rev-parse --verify --quiet origin/master > /dev/null || return 0
                if ! notmuch git merge origin/master; then
                  touch "$broken"
                  exit 1
                fi
              }

              git -C "$repo" fetch origin
              merge
              if ! git -C "$repo" push origin master; then
                # Lost a push race with the other device.
                git -C "$repo" fetch origin
                merge
                git -C "$repo" push origin master
              fi
            '';
          };
        in
        [
          # Expose the packages directly for testing.
          do-notmuch-propagate-mute
          sync-lkml-tags
          copy-lore-url
          pkgs.bjackman.notmuch-get-dead-addresses
          filter-dead-addresses
          (pkgs.writeShellApplication {
            name = "get-lkml";
            # For lei
            runtimeInputs = [
              pkgs.public-inbox
              pkgs.notmuch
              do-notmuch-propagate-mute
            ];
            # lei q does undocumented fucked up things inserting quotes into its
            # arguments. It's written in Perl. It seems not to shit the bed too
            # badly if you provide each "term" of the search query as separate
            # arguments. It also munges the date filter in a weird way that I
            # don't understand and which is buggy.
            text =
              let
                addressMatchers = map (addr: "a:${addr}") allAddresses;
                # The quoting shit above is also why this quoting is such a
                # mess, we want to send parens as individual arguments, need to
                # put them in quotes so that they don't get interpreted as a
                # subshell.
                addressTerm = ''"(" ${lib.concatStringsSep " OR " addressMatchers} ")"'';
              in
              ''
                lei q -I https://lore.kernel.org/all/ -o ${config.accounts.email.maildirBasePath}/lore \
                  --threads --dedupe=mid --augment \
                  ${addressTerm} 'AND' 'dt:20250204132159..'
                notmuch new
                do-notmuch-propagate-mute
              '';
          })
        ];

      systemd.user.services.get-lkml = {
        Unit = {
          Description = "Get LKML";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${config.home.path}/bin/get-lkml";
          Slice = "background.slice";
        };
      };

      systemd.user.timers.get-lkml = {
        Unit = {
          Description = "Timer for get-lkml";
        };
        Timer = {
          OnStartupSec = "5m";
          OnUnitActiveSec = "1h";
          RandomizedDelaySec = "300";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };

      systemd.user.services.sync-lkml-tags = {
        Unit = {
          Description = "Sync notmuch tags via Forgejo";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${config.home.path}/bin/sync-lkml-tags";
          Slice = "background.slice";
        };
      };

      systemd.user.timers.sync-lkml-tags = {
        Unit = {
          Description = "Timer for sync-lkml-tags";
        };
        Timer = {
          OnStartupSec = "2m";
          OnUnitActiveSec = "15m";
          RandomizedDelaySec = "60";
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    }
  );
}
