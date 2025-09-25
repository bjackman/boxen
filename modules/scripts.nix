{
  pkgs,
  ...
}:
{
  # TODO: https://discourse.nixos.org/t/multiple-packages-in-the-same-flake-that-depend-on-each-other/69673/3
  # Define these separately as flake outputs too
  home.packages =
    let
      spellcheck_commitmsg = pkgs.writeShellApplication {
        name = "spellcheck_commitmsg.sh";
        runtimeInputs = [
          pkgs.gnused
          pkgs.hunspell
        ];
        text = builtins.readFile ../src/spellcheck_commitmsg.sh;
      };
      spellcheck_commitmsgs = pkgs.writeShellApplication {
        name = "spellcheck_commitmsgs.sh";
        runtimeInputs = [
          spellcheck_commitmsg
          pkgs.b4
          pkgs.gnused
          pkgs.git
        ];
        text = builtins.readFile ../src/spellcheck_commitmsgs.sh;
      };
    in
    [
      spellcheck_commitmsg
      spellcheck_commitmsgs
    ];
}
