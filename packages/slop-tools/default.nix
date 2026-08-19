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
    "gerritHost=${gerritHost}"
    "gerritPort=${toString gerritPort}"
    "gerritURL=${gerritUrl}"
    "branch=${branch}"
    "pusher=${pusher}"
    "reviewer=${reviewer}"
    "keyFile=${keyFile}"
    "authUser=${authUser}"
    "passwordFile=${passwordFile}"
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
