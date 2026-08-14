{
  pkgs,
  lib,
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "notmuch-get-dead-addresses";
  nativeBuildInputs = [ pkgs.makeWrapper ];
  propagatedBuildInputs = [ pkgs.python3 ];
  dontUnpack = true;
  installPhase = "install -Dm755 ${./notmuch_get_dead_addresses.py} $out/bin/notmuch-get-dead-addresses";
  postFixup = ''
    wrapProgram $out/bin/notmuch-get-dead-addresses \
      --prefix PATH : ${lib.makeBinPath [ pkgs.notmuch ]}
  '';
}
