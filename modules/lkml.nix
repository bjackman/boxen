{ config, pkgs, lib, ... }:
{
  options = {
    # Home Manager also has accounts.email.maildirBasePath but since this setup
    # is kinda special, define a separate one specifically for LKML.
    lkml.maildirBasePath = lib.mkOption {
      type = lib.types.path;
      default = "${config.homeDirectory}/mail";
    };
  };
  config = {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "get-lkml";
        # For lei
        runtimeInputs = [ pkgs.public-inbox ];
        text = ''
          lei q -I https://lore.kernel.org/all/ -o ${config.lkml.maildirBasePath} \
            --threads --dedupe=mid --augment \
            '(a:jackmanb@google.com OR a:linux-mm@kvack.org OR a:x86@kernel.org) AND d:2025-04'
        '';
      })
    ];
  };
}