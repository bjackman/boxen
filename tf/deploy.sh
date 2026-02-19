# TODO: Get these from the NixOS configuration
export RADARR_URL=http://norte:9000
export SONARR_URL=http://norte:9003
export TF_VAR_bitmagnet_torznab_url=http://pizza:9000/torznab
export TF_VAR_transmission_username=brendan
export TF_VAR_transmission_port=9004

read_secret() {
    local name="$1"
    local var="$2"

    file="$XDG_RUNTIME_DIR/agenix/$name"
    if [ ! -f "$file" ]; then
        echo "$file not found, you probably need to import the homelab-ctrl Home Manager module."
        exit 1
    fi
    export "$var=$(cat "$file")"
}

read_secret "arr-api-key" RADARR_API_KEY
read_secret "arr-api-key" SONARR_API_KEY
read_secret "transmission-password" TF_VAR_transmission_password

cd "$HOME_MANAGER_CONFIG_CHECKOUT/tf"
tofu apply
