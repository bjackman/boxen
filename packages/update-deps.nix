{
  writeShellApplication,
  git,
  cargo,
  nodejs,
}:
writeShellApplication {
  name = "update-deps";
  # nix comes from PATH, so it's the host's own.
  runtimeInputs = [
    git
    cargo
    nodejs
  ];
  text = ''
    rootPath=$(git rev-parse --show-toplevel)
    cd "$rootPath"

    nix flake update

    cargo update --manifest-path packages/heating/Cargo.toml

    cd packages/slopops
    npm update --package-lock-only --ignore-scripts
    cd "$rootPath"

    git diff --stat -- flake.lock packages/heating packages/slopops
  '';
}
