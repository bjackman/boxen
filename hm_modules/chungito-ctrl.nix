# Mini helpers to power my home CC, Chungito on and off remotely from the
# command line.
# Note this assumes we are connected to my Tailnet, but nothing in this
# repository actually configures that.
{
  pkgs,
  config,
  agenix,
  ...
}:
{
  imports = [
    agenix.homeManagerModules.default
  ];
  # This is the configuration for decrypting secrets. This will cause the
  # secrets to be decrypted and dumped into a tmpfs as plaintext. The path of
  # that plaintext file will be available as
  # config.age.secrets."${name}".path.
  # Note that the key used to decrypt them is left implicit so it will look at
  # the general SSH configuration and pick a sensitible default.
  age.secrets = {
    eadbald-pikvm-password.file = ../secrets/eadbald-pikvm-password.age;
  };

  home.packages = [
    # Don't bother with `chungito-off` since that's just `ssh chungito poweroff`.
    (pkgs.writeShellApplication {
      name = "chungito-on";
      runtimeInputs = [ pkgs.curl ];
      text = ''
        set -o pipefail

        password=$(cat "${config.age.secrets.eadbald-pikvm-password.path}")
        curl -X POST -k -u admin:"$password" https://eadbald-pikvm.bonito-coho.ts.net/api/atx/power?action=on 
      '';
    })
    (pkgs.writeShellApplication {
      name = "chungito-status";
      runtimeInputs = [ pkgs.curl ];
      text = ''
        set -o pipefail

        password=$(cat "${config.age.secrets.eadbald-pikvm-password.path}")
        curl -X GET -k -u admin:"$password" https://eadbald-pikvm.bonito-coho.ts.net/api/atx
      '';
    })
  ];
}
