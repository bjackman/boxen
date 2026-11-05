{
  writeShellApplication,
  git,
  cargo,
  nodejs,
  jq,
}:
writeShellApplication {
  name = "update-deps";
  # nix comes from PATH, so it's the host's own.
  runtimeInputs = [
    git
    cargo
    nodejs
    jq
  ];
  text = ''
    rootPath=$(git rev-parse --show-toplevel)
    cd "$rootPath"

    nix flake update

    cargo update --manifest-path packages/heating/Cargo.toml

    # packages/slopops requires the Agent SDK's patch version to match
    # claude-code's.
    claudeCodeVersion=$(nix eval --raw .#slopops.claude-code.version)
    sdk=@anthropic-ai/claude-agent-sdk
    cd packages/slopops
    sdkVersion=$(jq -r --arg sdk "$sdk" '.dependencies[$sdk]' package.json)
    npm pkg set "dependencies.$sdk=''${sdkVersion%.*}.''${claudeCodeVersion##*.}"
    npm install --package-lock-only --ignore-scripts
    npm update --package-lock-only --ignore-scripts
    cd "$rootPath"

    git diff --stat -- flake.lock packages/heating packages/slopops
  '';
}
