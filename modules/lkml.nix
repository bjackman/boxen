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

    home.packages = [
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
