# My Home Manager config

## Secrets

Secrets are stored using [agenix](https://github.com/ryantm/agenix). At runtime
they get decrypted and dumpted into a tmpfs as plaintext (lol).

To add a secret, run `nix develop` to get the `agenix` CLI, then go into
`secrets/` and add it to `secrets.nix` following the existing pattern in there.
That's where you configure which keys can decrypt it. Then run `agenix -e
<name>.nix`. Then to make it get decrypted at runtime, add it to `age.secrets`
in the home-manager config.