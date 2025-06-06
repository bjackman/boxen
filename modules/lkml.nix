{
  config,
  pkgs,
  lib,
  ...
}:
{
  options = {
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
  config = {
    programs.notmuch = {
      enable = true;
      # No option to directly override the default which is
      # config.accounts.email.maildirBasePath.
      extraConfig = {
        database.path = config.lkml.maildirBasePath;
      };
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
      in
      [
        # Expose the package directly for testing.
        notmuch-propagate-mute
        (pkgs.writeShellApplication {
          name = "get-lkml";
          # For lei
          runtimeInputs = [
            pkgs.public-inbox
            pkgs.notmuch
          ];
          text = ''
            lei q -I https://lore.kernel.org/all/ -o ${config.lkml.maildirBasePath} \
              --threads --dedupe=mid --augment \
              '(a:jackmanb@google.com OR a:linux-mm@kvack.org OR a:x86@kernel.org) AND d:2025-04'
            notmuch new
          '';
        })
      ];
  };
}
