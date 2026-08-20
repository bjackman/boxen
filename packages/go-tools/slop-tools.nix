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

  # Built from probe.nix instead, configured for the probe key and host keys.
  # Built from here they would be unconfigured and shadow those in the profile.
  excludedPackages = [
    "cmd/slop-probe"
    "cmd/slop-probe-server"
  ];

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
    for cmd in slop-pr slop-reply; do
      wrapProgram $out/bin/$cmd --prefix PATH : ${
        lib.makeBinPath [
          git
          openssh
        ]
      }
    done
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
