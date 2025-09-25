{
  pkgs,
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "notmuch-propagate-mute";
  propagatedBuildInputs = [
    (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.notmuch ]))
  ];
  dontUnpack = true;
  installPhase = "install -Dm755 ${../src/notmuch_propagate_mute.py} $out/bin/notmuch-propagate-mute";
}
