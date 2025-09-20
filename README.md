# My Home Manager config

## Secrets

Secrets are stored using [agenix](https://github.com/ryantm/agenix). At runtime
they get decrypted and dumpted into a tmpfs as plaintext (lol).

To add a secret, run `nix develop` to get the `agenix` CLI, then go into
`secrets/` and add it to `secrets.nix` following the existing pattern in there.
That's where you configure which keys can decrypt it. Then run `agenix -e
<name>.age`. Then to make it get decrypted at runtime, add it to `age.secrets`
in the home-manager config.

To add a recipient key for a secret, update `secrets.nix` to include it in that
secret's `publicKeys`setting, then run `RULES=secrets/secrets.nix nix develop -c
agenix -r` from the root of the repo.

## Diffing configs

I haven't found a nice way to diff evaluated HM condigurations. Here's the
closest thing I found so far:

```bash
nix eval --json .#homeConfigurations.brendan.config.home.file | jq > before.json

nix eval --json .#homeConfigurations.brendan.config.home.file | jq > after.json

diff before.json after.json
```