# The CI runner, built from the go-tools module but packaged separately: it
# runs on the Gerrit host and has no business depending on the closure of the
# tools that drive Claude Code.
#
# Unlike its neighbours this takes no configuration: everything it needs is a
# flag, and the only caller is a systemd unit that can pass them.
{
  buildGoModule,
  git,
  lib,
  makeWrapper,
  nix,
  openssh,
}:
buildGoModule {
  pname = "gerrit-ci";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;

  # This also narrows the check phase, so the shared library keeps its
  # coverage under slop-tools and this tests only what it builds.
  subPackages = [ "cmd/gerrit-ci" ];

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/bin/gerrit-ci --prefix PATH : ${
      lib.makeBinPath [
        git
        nix
        openssh
      ]
    }
  '';
}
