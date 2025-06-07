# TODO: This is coupled with configuration in accounts.email.accounts.
# Probably the solution to that is to drop the usage of high-level aerc and
# notmuch configuration, and instead configure them directly via home.files in
# here.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  options = {
    lkml.enable = lib.mkEnableOption "lkml";
    # Home Manager also has accounts.email.maildirBasePath but since this setup
    # is kinda special, define a separate one specifically for LKML.
    lkml.maildirBasePath = lib.mkOption {
      type = lib.types.path;
      # Note in my old dotifles repo I was unable to set this due to notmuch not
      # expanding ~ or $HOME. But in Nix I can can set it as an absolute path
      # :).
      default = "${config.home.homeDirectory}/lkml";
    };
  };
  config = lib.mkIf config.lkml.enable (
      # TODO: can't be bothered to figure out multiple addresses, assert
      # there is only one.
      let
        account =
          let accounts = lib.attrValues config.accounts.email.accounts;
          in (assert (builtins.length accounts == 1); (lib.head accounts));
      in {
        programs.notmuch = {
          enable = true;
          # No option to directly override the default which is
          # config.accounts.email.maildirBasePath.
          extraConfig = {
            database.path = config.lkml.maildirBasePath;
          };
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

        # The HM packaging for Aerc call the setting "extraBinds", but actually
        # if you set it then those are the _only_ keybindings you yet.
        # If you don't set it, then Aerc will produce an initial keybinding
        # setup on first run. Therefore we don't set it here and instead we just
        # have a config file checked in.
        home.file."${config.xdg.configHome}/aerc/binds.conf" = {
          source = ../files/lkml/config/aerc/binds.conf;
        };

        # TODO: Defining packages directly here is messy. But I haven't figured out
        # the proper way to organise this.
        home.packages =
          let
            # Copied from
            # https://stackoverflow.com/questions/43837691/how-to-package-a-single-python-script-with-nix
            # Seems reasonably sensible??
            notmuch-propagate-mute = pkgs.stdenv.mkDerivation {
              name = "notmuch-propagate-mute";
              propagatedBuildInputs = [
                (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.notmuch ]))
              ];
              dontUnpack = true;
              installPhase = "install -Dm755 ${../src/notmuch_propagate_mute.py} $out/bin/notmuch-propagate-mute";
            };
            # Dumb wrapper so I don't have to code args into the binds.conf
            do-notmuch-propagate-mute = pkgs.writeShellApplication {
              name = "do-notmuch-propagate-mute";
              runtimeInputs = [ notmuch-propagate-mute ];
              text = ''
                notmuch-propagate-mute --email ${account.address} --db-path ${config.lkml.maildirBasePath} "$@"
              '';
            };
          in
          [
            # Expose the packages directly for testing.
            notmuch-propagate-mute
            do-notmuch-propagate-mute
            (pkgs.writeShellApplication {
              name = "get-lkml";
              # For lei
              runtimeInputs = [
                pkgs.public-inbox
                pkgs.notmuch
                notmuch-propagate-mute
                do-notmuch-propagate-mute
              ];
              # lei q does undocumented fucked up things inserting quotes into its
              # arguments. It's written in Perl. It seems not to shit the bed too
              # badly if you provide each "term" of the search query as separate
              # arguments. It also munges the date filter in a weird way that I
              # don't understand and which is buggy.
              text = ''
                lei q -I https://lore.kernel.org/all/ -o ${config.lkml.maildirBasePath} \
                  --threads --dedupe=mid --augment \
                  'a:${account.address}' 'AND' 'dt:20250204132159..'
                notmuch new
                do-notmuch-propagate-mute
              '';
            })
          ];
      });
  }
