# WIP: Need to figure out how to move the notmuch and aerc config from the
# overall mail accounts declaration into this file.
# Then, need to set up aerc's query-map. This is not supported by the HM
# packaging, it needs to be done manually.
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

    # Cargo culted from
    # https://github.com/nix-community/home-manager/blob/91287a0e9d42570754487b7e38c6697e15a9aab2/modules/programs/notmuch.nix#L179
    # The idea here is to add a accounts.email.accounts.$name.lkml.enable option
    # which will then apply all the other relevant account settings.
    # This will somewhat clobber any other email setup, it might break if you do
    # anything other than just set lkml.enable = true;
    accounts.email.accounts = lib.mkOption {
      type =
        with types;
        attrsOf (submodule {
          options.lkml.enable = lib.mkEnableOption "Fancy LKML-reading setup";
        });
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

    programs.aerc = {
      enable = true;
      # aerc is fussy about config permissions since you might put creds in
      # there. Nix doesn't support having the cautious permissions, but we won't
      # put creds in it (they would be leaked into the Nix store anyway).
      extraConfig.general.unsafe-accounts-conf = true;
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
            notmuch-propagate-mute
          ];
          text =
            # TODO: can't be bothered to figure out multiple addresses, assert
            # there is only one.
            let
              account =
                let accounts = lib.attrValues config.accounts.email.accounts;
                in (assert (builtins.length accounts == 1); (lib.head accounts));
            in ''
              lei q -I https://lore.kernel.org/all/ -o ${config.lkml.maildirBasePath} \
                --threads --dedupe=mid --augment \
                '(a:${account.address} OR a:linux-mm@kvack.org OR a:x86@kernel.org) AND d:2025-04'
              notmuch new
              notmuch-propagate-mute \
                --email ${account.address} --db-path ${config.lkml.maildirBasePath}
            '';
        })
      ];
  };
}
