{
  lib,
  stdenv,
  importNpmLock,
  nodejs,
  makeWrapper,
  writeText,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "slopops";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./mcp.mts
    ];
  };
  npmDeps = importNpmLock { npmRoot = ./.; };
  nativeBuildInputs = [
    importNpmLock.npmConfigHook
    nodejs
    makeWrapper
  ];

  installPhase = ''
    mkdir -p $out/lib/slopops
    cp -r node_modules mcp.mts package.json $out/lib/slopops/
    makeWrapper ${lib.getExe nodejs} $out/bin/slopops-mcp \
      --add-flags $out/lib/slopops/mcp.mts
  '';

  passthru.claudeConfig = import ./claude-config.nix {
    inherit lib writeText;
    slopops = finalAttrs.finalPackage;
  };

  meta.mainProgram = "slopops-mcp";
})
