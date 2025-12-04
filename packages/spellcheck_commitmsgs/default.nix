{ pkgs }:
pkgs.writeShellApplication {
  name = "spellcheck_commitmsgs.sh";
  runtimeInputs = [
    pkgs.bjackman.spellcheck_commitmsg
    pkgs.b4
    pkgs.gnused
    pkgs.git
  ];
  text = builtins.readFile ./spellcheck_commitmsgs.sh;
}
