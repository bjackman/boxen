{
  buildGoModule,
  claude-code,
  git,
  lib,
  makeWrapper,
  tmux,
  forgejoUrl ? "https://forgejo.home.yawn.io",
  owner ? "brendan",
  pusher ? "slopbot",
  reviewer ? "brendan",
  repos ? [ "boxen" ],
  passwordFile ? "/run/agenix/slopbot-forgejo-password",
  secretFile ? "/run/agenix/slopbot-webhook-secret",
}:
buildGoModule {
  pname = "slop-tools";
  version = "0.1.0";
  src = ./.;
  # No dependencies outside the standard library, so there's no vendor hash to
  # keep up to date.
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  ldflags = map (flag: "-X main.${flag}") [
    "forgejoURL=${forgejoUrl}"
    "owner=${owner}"
    "pusher=${pusher}"
    "reviewer=${reviewer}"
    "repos=${lib.concatStringsSep "," repos}"
    "passwordFile=${passwordFile}"
    "secretFile=${secretFile}"
  ];

  postFixup = ''
    wrapProgram $out/bin/slop-pr --prefix PATH : ${lib.makeBinPath [ git ]}
    wrapProgram $out/bin/slop-handler --prefix PATH : ${
      lib.makeBinPath [
        claude-code
        git
        tmux
      ]
    }
  '';
}
