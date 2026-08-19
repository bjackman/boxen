{
  buildGoModule,
  claude-code,
  git,
  lib,
  makeWrapper,
  openssh,
  tmux,
  gerritHost ? "pizza",
  gerritPort ? 29418,
  gerritUrl ? "https://gerrit.home.yawn.io",
  branch ? "master",
  pusher ? "slopbot",
  reviewer ? "brendan",
  keyFile ? "/run/agenix/slopbot-ssh-privkey",
  authUser ? "slopbot",
  passwordFile ? "/run/agenix/slopbot-authelia-password",
  # Still Forgejo-shaped until the handler is ported.
  forgejoUrl ? "https://forgejo.home.yawn.io",
  owner ? "brendan",
  repos ? [ "boxen" ],
  forgejoPasswordFile ? "/run/agenix/slopbot-forgejo-password",
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

  # The linker ignores a -X for a variable a binary doesn't have, so both
  # commands' settings can be passed together while the port is half done.
  ldflags = map (flag: "-X main.${flag}") [
    "gerritHost=${gerritHost}"
    "gerritPort=${toString gerritPort}"
    "gerritURL=${gerritUrl}"
    "branch=${branch}"
    "pusher=${pusher}"
    "reviewer=${reviewer}"
    "keyFile=${keyFile}"
    "authUser=${authUser}"
    "passwordFile=${passwordFile}"
    "forgejoURL=${forgejoUrl}"
    "owner=${owner}"
    "repos=${lib.concatStringsSep "," repos}"
    "forgejoPasswordFile=${forgejoPasswordFile}"
    "secretFile=${secretFile}"
  ];

  postFixup = ''
    wrapProgram $out/bin/slop-pr --prefix PATH : ${
      lib.makeBinPath [
        git
        openssh
      ]
    }
    wrapProgram $out/bin/slop-handler --prefix PATH : ${
      lib.makeBinPath [
        claude-code
        git
        openssh
        tmux
      ]
    }
  '';
}
