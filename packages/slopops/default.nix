{
  lib,
  stdenv,
  importNpmLock,
  nodejs,
  makeWrapper,
  resvg,
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
    resvg
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
    resvg -w 192 -h 192 chat/web/icon.svg chat/web/icon-192.png
    resvg -w 512 -h 512 chat/web/icon.svg chat/web/icon-512.png
    resvg -w 512 -h 512 chat/web/icon-maskable.svg chat/web/icon-maskable-512.png
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    npm prune --omit=dev --omit=optional
    mkdir -p $out/lib/slopops/chat/web
    cp -r node_modules mcp.mts package.json $out/lib/slopops/
    cp chat/server.mts chat/events.ts $out/lib/slopops/chat/
    cp chat/web/index.html chat/web/style.css chat/web/manifest.webmanifest chat/web/icon.svg \
      chat/web/icon-192.png chat/web/icon-512.png chat/web/icon-maskable-512.png \
      chat/web/dist/web/app.js chat/web/dist/sw.js $out/lib/slopops/chat/web/
    cp node_modules/marked/lib/marked.esm.js $out/lib/slopops/chat/web/marked.js
    makeWrapper ${lib.getExe nodejs} $out/bin/slopops-mcp \
      --add-flags $out/lib/slopops/mcp.mts
    makeWrapper ${lib.getExe nodejs} $out/bin/slopops-chat \
      --add-flags $out/lib/slopops/chat/server.mts \
      --set SLOPOPS_CHAT_WEB_DIR $out/lib/slopops/chat/web
    runHook postInstall
  '';

  passthru = {
    inherit claude-code;
    claudeConfig = import ./claude-config.nix {
      inherit lib writeText;
      slopops = finalAttrs.finalPackage;
    };
  };

  meta.mainProgram = "slopops-mcp";
})
