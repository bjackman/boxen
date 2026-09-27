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
  src = ./.;
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
