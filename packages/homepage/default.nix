{ pkgs, src }:

pkgs.runCommand "homepage" { nativeBuildInputs = [ pkgs.pandoc ]; } ''
  mkdir $out
  cp ${src}/style.css $out/
  pandoc ${src}/index.md \
    --standalone \
    --css style.css \
    -o $out/index.html
''
