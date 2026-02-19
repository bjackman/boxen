# TODO: Get this from the NixOS configuration
export RADARR_URL=http://norte:9000

read_secret() {
    local name="$1"
    local var="$2"

    file="$XDG_RUNTIME_DIR/agenix/$name"
    if [ ! -f "$file" ]; then
        echo "$file not found, you probably need to set up age.secrets.$name in your Home Manager config"
        exit 1
    fi
    export "$var=$(cat "$file")"
}

read_secret "arr-api-key" RADARR_API_KEY

cd "$HOME_MANAGER_CONFIG_CHECKOUT/tf"
tofu apply
