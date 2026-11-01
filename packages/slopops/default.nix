{
  lib,
  stdenv,
  importNpmLock,
  nodejs,
  makeWrapper,
  writeText,
  claude-code,
}:
let
  packageLock = lib.importJSON ./package-lock.json;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "slopops";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./mcp.mts
      ./chat
    ];
  };
  npmDeps = importNpmLock {
    npmRoot = ./.;
    # The Agent SDK's builds of the CLI, one per platform: it runs Nix's
    # claude instead.
    packageLock = packageLock // {
      packages = lib.filterAttrs (
        path: _: !lib.hasPrefix "node_modules/@anthropic-ai/claude-agent-sdk-" path
      ) packageLock.packages;
    };
  };
  npmInstallFlags = [ "--omit=optional" ];
  nativeBuildInputs = [
    importNpmLock.npmConfigHook
    nodejs
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    sdkPackagePath=node_modules/@anthropic-ai/claude-agent-sdk/package.json
    wantedVersion=$(node -p "require('./$sdkPackagePath').claudeCodeVersion")
    if [ "$wantedVersion" != ${claude-code.version} ]; then
      echo "The Agent SDK is built for claude-code $wantedVersion, not ${claude-code.version}: run update-deps" >&2
      exit 1
    fi
    node_modules/.bin/tsc -p chat/tsconfig.json
    node_modules/.bin/tsc -p chat/web/tsconfig.json
    node_modules/.bin/tsc -p chat/web/sw.tsconfig.json
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    npm prune --omit=dev --omit=optional
    mkdir -p $out/lib/slopops/chat/web
    cp -r node_modules mcp.mts package.json $out/lib/slopops/
    cp chat/server.mts chat/events.ts $out/lib/slopops/chat/
    cp chat/web/index.html chat/web/style.css chat/web/manifest.webmanifest chat/web/icon.svg \
      chat/web/dist/web/app.js chat/web/dist/sw.js $out/lib/slopops/chat/web/
    makeWrapper ${lib.getExe nodejs} $out/bin/slopops-mcp \
      --add-flags $out/lib/slopops/mcp.mts
    makeWrapper ${lib.getExe nodejs} $out/bin/slopops-chat \
      --add-flags $out/lib/slopops/chat/server.mts \
      --set SLOPOPS_CHAT_WEB_DIR $out/lib/slopops/chat/web
    runHook postInstall
  '';

  passthru.claudeConfig = import ./claude-config.nix {
    inherit lib writeText;
    slopops = finalAttrs.finalPackage;
  };

  meta.mainProgram = "slopops-mcp";
})
