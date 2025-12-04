{ pkgs }:
pkgs.writeShellApplication {
  name = "spellcheck_commitmsg.sh";
  runtimeInputs = [
    pkgs.gnused
    pkgs.hunspell
  ];
  text = builtins.readFile ./spellcheck_commitmsg.sh;
}
