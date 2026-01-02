{ lib, pkgs, ... }:

pkgs.writeShellApplication rec {
  name = "add-user";

  runtimeInputs = with pkgs; [
    openssl
    agenix
    jq
    authelia
    moreutils
  ];

  text = ''
    USERNAME="$1"

    if ! [[ "$USERNAME" =~ ^[a-z]+$ ]]; then
      echo "To use non-alphabetical characters, update the displayName option in iap.nix"
      exit 1
    fi

    PASSWORD=$(openssl rand -base64 12)
    HASH="$(authelia crypto hash generate argon2 --password "$PASSWORD" | awk '{print $2}')"

    # Create base user definition
    JSON=nixos_modules/iap_users.json
    jq --arg user "$USERNAME" '.[$user] = {}' "$JSON" | sponge "$JSON"

    # Add Authelia password
    (
      cd ./secrets
      JSON=authelia/passwords.json.age
      agenix --decrypt "$JSON" | \
        jq --arg user "$USERNAME" --arg hash "$HASH" '.[$user] = $hash' | \
        agenix -e "$JSON"
    )

    echo "User '$USERNAME' added successfully."
    echo "Password: $PASSWORD"
  '';
}
