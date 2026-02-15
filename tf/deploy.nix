# Terranix lets you write your Terraform in HCL instead of Nix and that would
# seem to let you share data with the rest of this repo via the NixOS modules
# system, which seems pretty neat.
# But, it seems like you'd still have to write a wrapper to deal with setting up
# secrets. So.. here's that wrapper anyway, and instead of using Terranix it
# just wraps the normal OpenTofu mechanism. We still get to share data with the
# rest of the config we just have to do it via slightly more verbose Terraform
# variables.
# Note this package only works on machines with the Agenix secrets mounted, and
# it assumes the configuration is $HOME_MANAGER_CONFIG_CHECKOUT (i.e. this is
# really tightly coupled with the rest of the repo).
# Note it's possible some of this magic is not really necessary because TF can
# store secrets in the state file - so we'd actually only need to inject
# variables once. But then if the value changed we'd need to remember to update
# the state. So we just set up the environment completely every time.
{ pkgs }:
pkgs.writeShellApplication {
  name = "deploy-tf";
  runtimeInputs = with pkgs; [ opentofu ];
  text = ''
    # TODO: Get this from the NixOS configuration
    export RADARR_URL=http://norte:9000

    api_key_file="$XDG_RUNTIME_DIR/agenix/arr-api-key"
    if [ ! -f "$api_key_file" ]; then
      echo "$api_key_file not found, you probably need to set up age.secrets.arr-api-key in your Home Manager config"
      exit 1
    fi
    RADARR_API_KEY=$(cat "$api_key_file")
    export RADARR_API_KEY

    # TODO: Get the password from an Agenix secret

    cd "$HOME_MANAGER_CONFIG_CHECKOUT/tf"
    tofu apply
  '';
}
