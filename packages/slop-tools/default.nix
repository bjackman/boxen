{
  buildGoModule,
  git,
  lib,
  makeWrapper,
  forgejoUrl ? "https://forgejo.home.yawn.io",
  owner ? "brendan",
  pusher ? "slopbot",
  passwordFile ? "/run/agenix/slopbot-forgejo-password",
}:
buildGoModule {
  pname = "slop-tools";
  version = "0.1.0";
  src = ./.;
  # No dependencies outside the standard library, so there's no vendor hash to
  # keep up to date.
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  ldflags = [
    "-X main.forgejoURL=${forgejoUrl}"
    "-X main.owner=${owner}"
    "-X main.pusher=${pusher}"
    "-X main.passwordFile=${passwordFile}"
  ];

  postFixup = ''
    wrapProgram $out/bin/slop-pr --prefix PATH : ${lib.makeBinPath [ git ]}
  '';
}
