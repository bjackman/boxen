{
  stdenv,
  rustc,
}:
stdenv.mkDerivation {
  pname = "capslock-watch";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ rustc ];
  buildPhase = "rustc --edition 2021 -O -o capslock-watch main.rs";
  installPhase = "install -Dm755 capslock-watch $out/bin/capslock-watch";
}
