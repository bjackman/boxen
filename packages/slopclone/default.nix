{ pkgs, ... }:
pkgs.writeShellScriptBin "slopclone" (builtins.readFile ./slopclone.sh)