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
  # Only what these commands import, so that the rest of the module changing
  # doesn't restart the agents that have this on their PATH. The other commands
  # are built from probe.nix and gerrit-ci.nix instead.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./gerrit
      ./internal/session
      ./cmd/slop-handler
      ./cmd/slop-pr
      ./cmd/slop-reply
    ];
  };
  # No dependencies outside the standard library, so there's no vendor hash to
  # keep up to date.
  vendorHash = null;

  nativeBuildInputs = [ makeWrapper ];

  # Configuration is flags rather than ldflags: it stays visible in the
  # wrapper, overridable for a one-off, and changing it doesn't rebuild Go.
  flags = lib.escapeShellArgs [
    "--gerrit-host=${gerritHost}"
    "--gerrit-port=${toString gerritPort}"
    "--gerrit-url=${gerritUrl}"
    "--branch=${branch}"
    "--pusher=${pusher}"
    "--reviewer=${reviewer}"
    "--key-file=${keyFile}"
    "--auth-user=${authUser}"
    "--password-file=${passwordFile}"
  ];

  postFixup = ''
    for cmd in slop-pr slop-reply; do
      wrapProgram $out/bin/$cmd --add-flags "$flags" --prefix PATH : ${
        lib.makeBinPath [
          git
          openssh
        ]
      }
    done
    wrapProgram $out/bin/slop-handler --add-flags "$flags" --prefix PATH : ${
      lib.makeBinPath [
        claude-code
        git
        openssh
        tmux
      ]
    }
  '';
}
