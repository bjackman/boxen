{
  buildGoModule,
  claude-code,
  git,
  lib,
  makeWrapper,
  openssh,
}:
buildGoModule {
  pname = "review-bot";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./gerrit
      ./internal/review
      ./cmd/review-bot
    ];
  };
  vendorHash = null;

  subPackages = [ "cmd/review-bot" ];

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/bin/review-bot --prefix PATH : ${
      lib.makeBinPath [
        claude-code
        git
        openssh
      ]
    }
  '';
}
