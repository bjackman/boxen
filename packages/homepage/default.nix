{ pkgs, src }:

pkgs.runCommand "homepage" { nativeBuildInputs = [ pkgs.pandoc ]; } ''
  mkdir $out
  cp -R ${src}/assets/ $out/
  pandoc ${src}/index.md \
    --standalone \
    --css assets/style.css \
    -o $out/index.html
''
